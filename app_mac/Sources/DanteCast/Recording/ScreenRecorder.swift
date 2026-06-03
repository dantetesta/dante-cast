import Foundation
import AVFoundation
import CoreVideo
import CoreMedia

/// Grava os CVPixelBuffers decodificados em um arquivo .mov via AVAssetWriter,
/// com opção de incluir o áudio do microfone do Mac (narração).
///
/// Sincronização: vídeo e áudio são carimbados no MESMO relógio (host time clock).
/// Como o vídeo chega com PTS do Android (outra base de tempo) e o áudio do microfone
/// usa o relógio de captura do Mac, re-carimbamos o vídeo no host clock para que ambos
/// compartilhem uma única timeline — caso contrário a faixa de áudio ficaria dessincronizada.
///
/// Modo da faixa de áudio na gravação.
enum RecordingAudio {
    case none           // só vídeo
    case microphone     // narração via microfone do Mac (captura AVCaptureSession)
    case device(sampleRate: Double, channels: Int)  // áudio interno do device (PCM int16 LE)
}

/// Uso:
///   start(in:size:audio:) -> append(pixelBuffer:pts:) por frame
///   [+ appendDevicePCM(...) quando audio == .device] -> stop { url,dur in ... }
final class ScreenRecorder {

    private(set) var isRecording = false
    private(set) var outputURL: URL?

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?

    // Áudio (opcional).
    private var audioInput: AVAssetWriterInput?
    private var captureSession: AVCaptureSession?
    private let audioTap = AudioTap()
    private let audioQueue = DispatchQueue(label: "com.dantetesta.dantecast.recorder.audio")

    // Áudio do device (PCM int16 LE): format description + posição na timeline do host clock.
    private var deviceAudioFormat: CMAudioFormatDescription?
    private var deviceAudioSampleRate: Double = 0
    private var deviceAudioChannels: Int = 0

    private var sessionStarted = false
    private var startHostTime: CMTime = .zero
    private var startDate: Date?
    private let lock = NSLock()

    /// Relógio de referência (host time) compartilhado por vídeo e áudio.
    private let hostClock = CMClockGetHostTimeClock()
    private func nowHostTime() -> CMTime { CMClockGetTime(hostClock) }

    /// Inicia a gravação. `size` deve casar com o tamanho dos pixel buffers.
    /// `audio` escolhe a faixa de áudio (nenhuma, microfone, ou áudio do device).
    /// Qualquer falha de áudio degrada para vídeo-only (sem crash).
    /// Retorna a URL de destino ou nil em caso de falha.
    @discardableResult
    func start(in folder: URL, size: CGSize, audio: RecordingAudio = .none) -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard !isRecording else { return outputURL }
        guard size.width > 0, size.height > 0 else { return nil }
        deviceAudioFormat = nil

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "DanteCast_\(formatter.string(from: Date())).mov"
        let url = folder.appendingPathComponent(fileName)

        do {
            let w = try AVAssetWriter(outputURL: url, fileType: .mov)

            // ---- Faixa de vídeo ----
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height)
            ]
            let inp = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            inp.expectsMediaDataInRealTime = true

            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
            let adp = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: inp,
                sourcePixelBufferAttributes: attrs)

            guard w.canAdd(inp) else { return nil }
            w.add(inp)

            // ---- Faixa de áudio (opcional, best-effort) ----
            self.audioInput = nil
            switch audio {
            case .none:
                break
            case .microphone:
                if let aInput = setupAudioCapture(), w.canAdd(aInput) {
                    w.add(aInput)
                    self.audioInput = aInput
                }
            case .device(let sr, let ch):
                if let aInput = setupDeviceAudioInput(sampleRate: sr, channels: ch),
                   w.canAdd(aInput) {
                    w.add(aInput)
                    self.audioInput = aInput
                }
            }

            guard w.startWriting() else {
                Log.record.error("startWriting falhou: \(String(describing: w.error))")
                teardownAudioLocked()
                return nil
            }

            self.writer = w
            self.input = inp
            self.adaptor = adp
            self.sessionStarted = false
            self.startDate = Date()
            self.outputURL = url
            self.isRecording = true

            // Começa a captura de áudio depois que o writer está pronto.
            captureSession?.startRunning()

            Log.record.info("Gravação iniciada: \(url.lastPathComponent) (áudio: \(self.audioInput != nil))")
            return url
        } catch {
            Log.record.error("Falha ao criar AVAssetWriter: \(error.localizedDescription)")
            teardownAudioLocked()
            return nil
        }
    }

    /// Acrescenta um frame de vídeo. O PTS do stream é IGNORADO para a gravação:
    /// usamos o host clock (mesma base do áudio) para manter A/V em sincronia.
    func append(pixelBuffer: CVPixelBuffer, pts: CMTime) {
        lock.lock()
        guard isRecording, let adaptor = adaptor, let input = input else { lock.unlock(); return }

        let now = nowHostTime()
        if !sessionStarted {
            writer?.startSession(atSourceTime: now)
            startHostTime = now
            sessionStarted = true
        }
        let ready = input.isReadyForMoreMediaData
        lock.unlock()

        guard ready else { return }   // dropa o frame se o writer está saturado
        adaptor.append(pixelBuffer, withPresentationTime: now)
    }

    /// Finaliza e devolve (url, duração em segundos) no completion.
    func stop(completion: @escaping (URL?, Int) -> Void) {
        lock.lock()
        guard isRecording, let writer = writer, let input = input else {
            lock.unlock(); completion(nil, 0); return
        }
        isRecording = false
        let url = outputURL
        let duration = startDate.map { Int(Date().timeIntervalSince($0)) } ?? 0
        let aInput = audioInput
        lock.unlock()

        // Para a captura de áudio.
        captureSession?.stopRunning()
        aInput?.markAsFinished()
        input.markAsFinished()

        writer.finishWriting { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.writer = nil; self.input = nil; self.adaptor = nil
            self.audioInput = nil
            self.sessionStarted = false
            self.teardownAudioLocked()
            self.lock.unlock()
            Log.record.info("Gravação finalizada (\(duration)s)")
            DispatchQueue.main.async { completion(url, duration) }
        }
    }

    // MARK: - Áudio do microfone

    /// Monta a captura de áudio (microfone) e o input de áudio do writer.
    /// Retorna nil (e a gravação segue só com vídeo) se não houver permissão/dispositivo.
    private func setupAudioCapture() -> AVAssetWriterInput? {
        // Só prossegue se já autorizado (a permissão é solicitada antes, no AppState).
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let device = AVCaptureDevice.default(for: .audio),
              let deviceInput = try? AVCaptureDeviceInput(device: device) else {
            Log.record.info("Áudio indisponível (sem permissão/dispositivo) — gravando só vídeo.")
            return nil
        }

        let session = AVCaptureSession()
        guard session.canAddInput(deviceInput) else { return nil }
        session.addInput(deviceInput)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(audioTap, queue: audioQueue)
        guard session.canAddOutput(output) else { return nil }
        session.addOutput(output)

        self.captureSession = session

        // Input AAC para o .mov (o writer transcodifica o LPCM do microfone).
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 96_000
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true

        // Encaminha cada sample de áudio para o writer (na timeline do host clock).
        audioTap.onSample = { [weak self] sampleBuffer in
            guard let self = self else { return }
            self.lock.lock()
            let ok = self.isRecording && self.sessionStarted && aInput.isReadyForMoreMediaData
            self.lock.unlock()
            guard ok else { return }
            aInput.append(sampleBuffer)
        }
        return aInput
    }

    private func teardownAudioLocked() {
        audioTap.onSample = nil
        captureSession?.stopRunning()
        captureSession = nil
        deviceAudioFormat = nil
    }

    // MARK: - Áudio do device (PCM int16 LE)

    /// Monta o input de áudio (AAC) para o áudio interno do device e cacheia o
    /// CMAudioFormatDescription do PCM de entrada (int16 LE intercalado).
    private func setupDeviceAudioInput(sampleRate: Double, channels: Int) -> AVAssetWriterInput? {
        guard sampleRate > 0, channels > 0 else { return nil }

        // ASBD do PCM de entrada: int16 LE intercalado (signed, packed).
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(2 * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 16,
            mReserved: 0)

        var fmt: CMAudioFormatDescription?
        let st = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &fmt)
        guard st == noErr, let fmt = fmt else {
            Log.record.error("Áudio do device: falha ao criar format description (\(st)).")
            return nil
        }
        self.deviceAudioFormat = fmt
        self.deviceAudioSampleRate = sampleRate
        self.deviceAudioChannels = channels

        // Input AAC no .mov (o writer transcodifica o LPCM do device).
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: channels,
            AVSampleRateKey: sampleRate,
            AVEncoderBitRateKey: 128_000
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true
        return aInput
    }

    /// Acrescenta um bloco de PCM (int16 LE intercalado) do device à faixa de áudio.
    /// Carimba no host clock (mesma timeline do vídeo) para manter A/V em sincronia.
    func appendDevicePCM(_ pcm: Data) {
        lock.lock()
        guard isRecording, sessionStarted,
              let aInput = audioInput, let fmt = deviceAudioFormat,
              aInput.isReadyForMoreMediaData, !pcm.isEmpty else { lock.unlock(); return }
        let channels = deviceAudioChannels
        lock.unlock()

        let bytesPerFrame = 2 * channels
        guard bytesPerFrame > 0 else { return }
        let numFrames = pcm.count / bytesPerFrame
        guard numFrames > 0 else { return }
        let usableBytes = numFrames * bytesPerFrame

        // CMBlockBuffer com cópia única dos bytes de PCM.
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: usableBytes, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: usableBytes,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block) == kCMBlockBufferNoErr, let block = block else { return }

        let copyOK = pcm.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return CMBlockBufferReplaceDataBytes(
                with: base, blockBuffer: block,
                offsetIntoDestination: 0, dataLength: usableBytes) == kCMBlockBufferNoErr
        }
        guard copyOK else { return }

        // PTS na timeline do host clock.
        let pts = nowHostTime()
        var sample: CMSampleBuffer?
        let st = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: fmt,
            sampleCount: numFrames,
            presentationTimeStamp: pts,
            packetDescriptions: nil,
            sampleBufferOut: &sample)
        guard st == noErr, let sample = sample else { return }
        aInput.append(sample)
    }
}

/// Delegate de captura de áudio: repassa os CMSampleBuffers ao recorder.
private final class AudioTap: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var onSample: ((CMSampleBuffer) -> Void)?
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onSample?(sampleBuffer)
    }
}
