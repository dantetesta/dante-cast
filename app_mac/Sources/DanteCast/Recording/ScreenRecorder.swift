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
/// Uso:
///   start(in:size:includeAudio:) -> append(pixelBuffer:pts:) por frame -> stop { url,dur in ... }
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

    private var sessionStarted = false
    private var startHostTime: CMTime = .zero
    private var startDate: Date?
    private let lock = NSLock()

    /// Relógio de referência (host time) compartilhado por vídeo e áudio.
    private let hostClock = CMClockGetHostTimeClock()
    private func nowHostTime() -> CMTime { CMClockGetTime(hostClock) }

    /// Inicia a gravação. `size` deve casar com o tamanho dos pixel buffers.
    /// `includeAudio` ativa a captura do microfone (degrada para vídeo-only se falhar).
    /// Retorna a URL de destino ou nil em caso de falha.
    @discardableResult
    func start(in folder: URL, size: CGSize, includeAudio: Bool = false) -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard !isRecording else { return outputURL }
        guard size.width > 0, size.height > 0 else { return nil }

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
            if includeAudio, let aInput = setupAudioCapture(), w.canAdd(aInput) {
                w.add(aInput)
                self.audioInput = aInput
            } else {
                self.audioInput = nil
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
