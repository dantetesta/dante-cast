import Foundation
import AVFoundation
import CoreVideo
import CoreMedia

/// Grava os CVPixelBuffers decodificados em um arquivo .mov via AVAssetWriter.
///
/// Uso:
///   start(folder:size:) -> append(pixelBuffer:pts:) por frame -> stop { url in ... }
final class ScreenRecorder {

    private(set) var isRecording = false
    private(set) var outputURL: URL?

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var sessionStarted = false
    private var startTime: CMTime = .zero
    private var startDate: Date?
    private let lock = NSLock()

    /// Inicia a gravação. `size` deve casar com o tamanho dos pixel buffers.
    /// Retorna a URL de destino ou nil em caso de falha.
    @discardableResult
    func start(in folder: URL, size: CGSize) -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard !isRecording else { return outputURL }
        guard size.width > 0, size.height > 0 else { return nil }

        // Garante a pasta.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "DanteCast_\(formatter.string(from: Date())).mov"
        let url = folder.appendingPathComponent(fileName)

        do {
            let w = try AVAssetWriter(outputURL: url, fileType: .mov)

            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height)
            ]
            let inp = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
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
            guard w.startWriting() else {
                Log.record.error("startWriting falhou: \(String(describing: w.error))")
                return nil
            }

            self.writer = w
            self.input = inp
            self.adaptor = adp
            self.sessionStarted = false
            self.startDate = Date()
            self.outputURL = url
            self.isRecording = true
            Log.record.info("Gravação iniciada: \(url.lastPathComponent)")
            return url
        } catch {
            Log.record.error("Falha ao criar AVAssetWriter: \(error.localizedDescription)")
            return nil
        }
    }

    /// Acrescenta um frame. `pts` em CMTime (timescale us). Chamado por frame decodificado.
    func append(pixelBuffer: CVPixelBuffer, pts: CMTime) {
        lock.lock()
        guard isRecording, let adaptor = adaptor, let input = input else { lock.unlock(); return }

        let usePts = pts.isValid ? pts : CMTime(value: 0, timescale: 1_000_000)
        if !sessionStarted {
            writer?.startSession(atSourceTime: usePts)
            startTime = usePts
            sessionStarted = true
        }
        let ready = input.isReadyForMoreMediaData
        lock.unlock()

        guard ready else { return }   // dropa o frame se o writer está saturado
        adaptor.append(pixelBuffer, withPresentationTime: usePts)
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
        lock.unlock()

        input.markAsFinished()
        writer.finishWriting { [weak self] in
            self?.lock.lock()
            self?.writer = nil; self?.input = nil; self?.adaptor = nil
            self?.sessionStarted = false
            self?.lock.unlock()
            Log.record.info("Gravação finalizada (\(duration)s)")
            DispatchQueue.main.async { completion(url, duration) }
        }
    }
}
