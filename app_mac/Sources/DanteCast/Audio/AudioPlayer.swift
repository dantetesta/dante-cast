import Foundation
import AVFoundation

/// Reprodução do áudio interno do device Android no Mac.
///
/// Pipeline:
///  - AUDIO_CONFIG -> monta um AVAudioFormat de ENTRADA (int16 LE intercalado) e
///    (re)inicia um AVAudioEngine + AVAudioPlayerNode ligado ao mainMixer (saída Float32).
///  - AUDIO_FRAME -> converte int16 LE -> Float32 e agenda no player node em FIFO.
///
/// Robustez: se o engine falhar a qualquer momento, o áudio é simplesmente
/// descartado (NUNCA derruba o app nem bloqueia a rede). Todo o estado é
/// protegido por um lock pois os frames chegam na fila do servidor.
final class AudioPlayer {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    // Formato de entrada (PCM do device) e de saída (mixer, Float32).
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    private var isEngineRunning = false
    private var attached = false
    private let lock = NSLock()

    // Volume desejado (0...1) e mute, aplicados ao player node.
    private var _volume: Float = 1.0
    private var _muted = false

    init() {
        // Anexa o player uma única vez; conexões reais acontecem no configure().
        engine.attach(player)
        attached = true
    }

    deinit { teardown() }

    // MARK: - API pública

    /// (Re)configura o pipeline para o formato anunciado pelo device.
    /// Chamado na fila do servidor; faz teardown/rebuild de forma segura.
    func configure(sampleRate: Double, channels: AVAudioChannelCount, interleaved: Bool = true) {
        lock.lock(); defer { lock.unlock() }

        // Formato de entrada: int16 LE intercalado, conforme o protocolo.
        guard let inFmt = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                        sampleRate: sampleRate,
                                        channels: channels,
                                        interleaved: interleaved) else {
            Log.app.error("Áudio: formato de entrada inválido — ignorando.")
            return
        }

        // Para tudo antes de reconfigurar (troca de formato exige reconectar nós).
        stopLocked()

        // Formato de saída = formato nativo do mainMixer (Float32 não-intercalado).
        let mixer = engine.mainMixerNode
        let outFmt = mixer.outputFormat(forBus: 0)
        self.inputFormat = inFmt
        self.outputFormat = outFmt
        self.converter = AVAudioConverter(from: inFmt, to: outFmt)

        // Conecta o player ao mixer no formato de SAÍDA (já convertido).
        engine.connect(player, to: mixer, format: outFmt)

        do {
            engine.prepare()
            try engine.start()
            isEngineRunning = true
            applyVolumeLocked()
            player.play()
            Log.app.info("Áudio do device iniciado: \(Int(sampleRate))Hz, \(channels)ch")
        } catch {
            // Degrada graciosamente: sem áudio, mas o app segue.
            isEngineRunning = false
            Log.app.error("Áudio: falha ao iniciar engine — \(error.localizedDescription)")
        }
    }

    /// Agenda um frame de PCM (int16 LE intercalado) para reprodução.
    /// Chamado na fila do servidor; nunca bloqueia (apenas enfileira no node).
    func enqueue(pcm: Data) {
        lock.lock()
        guard isEngineRunning, let inFmt = inputFormat,
              let outFmt = outputFormat, let converter = converter,
              !pcm.isEmpty else { lock.unlock(); return }
        lock.unlock()

        // Quantidade de frames de amostra na entrada.
        let bytesPerFrame = Int(inFmt.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return }
        let inFrameCount = AVAudioFrameCount(pcm.count / bytesPerFrame)
        guard inFrameCount > 0 else { return }

        // Buffer de entrada int16 e cópia dos bytes (respeitando o LE nativo do Mac).
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: inFrameCount) else { return }
        inBuf.frameLength = inFrameCount
        let copyCount = Int(inFrameCount) * bytesPerFrame
        if let dst = inBuf.int16ChannelData?[0] {
            pcm.withUnsafeBytes { raw in
                if let src = raw.baseAddress {
                    // O Mac (arm64/x86) é little-endian -> cópia direta preserva os samples.
                    memcpy(dst, src, copyCount)
                }
            }
        }

        // Buffer de saída Float32 com capacidade proporcional à taxa.
        let ratio = outFmt.sampleRate / inFmt.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inFrameCount) * ratio) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: outCapacity) else { return }

        // Converte int16 LE -> Float32 (uma só passada por frame).
        var supplied = false
        var convErr: NSError?
        let status = converter.convert(to: outBuf, error: &convErr) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return inBuf
        }
        guard status != .error, outBuf.frameLength > 0 else { return }

        // Agenda em FIFO no player node (completa naturalmente; sem callback).
        player.scheduleBuffer(outBuf, completionHandler: nil)
    }

    /// Define o volume (0...1).
    func setVolume(_ value: Float) {
        lock.lock()
        _volume = max(0, min(1, value))
        applyVolumeLocked()
        lock.unlock()
    }

    /// Liga/desliga o mute (mantém o volume desejado).
    func setMuted(_ muted: Bool) {
        lock.lock()
        _muted = muted
        applyVolumeLocked()
        lock.unlock()
    }

    /// Para e desmonta tudo (ao desconectar).
    func teardown() {
        lock.lock()
        stopLocked()
        inputFormat = nil
        outputFormat = nil
        converter = nil
        lock.unlock()
    }

    // MARK: - Interno

    private func applyVolumeLocked() {
        player.volume = _muted ? 0 : _volume
    }

    private func stopLocked() {
        if isEngineRunning {
            player.stop()
            engine.stop()
            isEngineRunning = false
        }
    }
}
