import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// Decodificador H.264 via VideoToolbox.
///
/// Fluxo:
///  1. VIDEO_CONFIG -> extrai SPS/PPS -> cria CMVideoFormatDescription
///     (CMVideoFormatDescriptionCreateFromH264ParameterSets, nalUnitHeaderLength = 4)
///     -> cria VTDecompressionSession.
///  2. VIDEO_FRAME -> converte Annex-B em AVCC -> monta CMBlockBuffer/CMSampleBuffer
///     -> VTDecompressionSessionDecodeFrame -> callback entrega CVPixelBuffer.
///
/// É necessário um keyframe (IDR) para começar a decodificar.
final class H264Decoder {

    /// Callback chamado a cada frame decodificado (thread arbitrária).
    var onDecodedFrame: ((CVPixelBuffer, CMTime) -> Void)?
    /// Callback de erro fatal de decode.
    var onError: ((String) -> Void)?

    private var formatDescription: CMVideoFormatDescription?
    private var session: VTDecompressionSession?

    // Dimensões anunciadas no config (para logging/recorder).
    private(set) var width: Int = 0
    private(set) var height: Int = 0

    private var receivedKeyframe = false
    private let lock = NSLock()

    deinit { invalidate() }

    // MARK: - Configuração

    /// Configura a partir do payload VIDEO_CONFIG (SPS/PPS em Annex-B).
    func configure(with config: VideoConfigPayload) {
        lock.lock(); defer { lock.unlock() }

        guard let (sps, pps) = AnnexBParser.extractParameterSets(config.annexB) else {
            onError?("VIDEO_CONFIG sem SPS/PPS válidos")
            return
        }

        self.width = Int(config.width)
        self.height = Int(config.height)

        // Destrói sessão anterior (reconfiguração / resolução nova).
        teardownLocked()

        // Cria o format description a partir dos parameter sets.
        var formatDesc: CMVideoFormatDescription?
        let status: OSStatus = sps.withUnsafeBytes { spsRaw in
            pps.withUnsafeBytes { ppsRaw in
                let spsPtr = spsRaw.bindMemory(to: UInt8.self).baseAddress!
                let ppsPtr = ppsRaw.bindMemory(to: UInt8.self).baseAddress!
                let pointers: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
                let sizes: [Int] = [sps.count, pps.count]
                return pointers.withUnsafeBufferPointer { ptrBuf in
                    sizes.withUnsafeBufferPointer { sizeBuf in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: ptrBuf.baseAddress!,
                            parameterSetSizes: sizeBuf.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &formatDesc)
                    }
                }
            }
        }

        guard status == noErr, let fmt = formatDesc else {
            onError?("Falha ao criar CMVideoFormatDescription (status \(status))")
            return
        }
        self.formatDescription = fmt

        // Atributos do pixel buffer de saída: BGRA, compatível com Metal/CoreImage.
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decoderOutputCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var newSession: VTDecompressionSession?
        let sessStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: fmt,
            decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &newSession)

        guard sessStatus == noErr, let sess = newSession else {
            onError?("Falha ao criar VTDecompressionSession (status \(sessStatus))")
            return
        }
        self.session = sess
        self.receivedKeyframe = false
        Log.decoder.info("Decoder configurado \(self.width)x\(self.height)")
    }

    // MARK: - Decode de frame

    /// Decodifica um VIDEO_FRAME. Ignora frames até receber o primeiro keyframe.
    func decode(frame: VideoFramePayload) {
        lock.lock()
        let sess = session
        let fmt = formatDescription
        lock.unlock()

        guard let session = sess, let fmt = fmt else {
            return // ainda não configurado
        }

        // Precisa de um IDR para iniciar a decodificação.
        if !receivedKeyframe {
            if frame.isKeyframe {
                receivedKeyframe = true
            } else {
                return
            }
        }

        // Annex-B -> NAL units -> AVCC.
        let units = AnnexBParser.parseNALUnits(frame.annexB)
        let avcc = AnnexBParser.toAVCC(units)
        guard !avcc.isEmpty else { return }

        // Monta um CMBlockBuffer com os dados AVCC.
        var blockBuffer: CMBlockBuffer?
        let avccBytes = [UInt8](avcc)
        var mutableBytes = avccBytes
        let createStatus = mutableBytes.withUnsafeMutableBytes { raw -> OSStatus in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: raw.baseAddress,
                blockLength: raw.count,
                blockAllocator: kCFAllocatorNull, // não libera nossa memória
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: raw.count,
                flags: 0,
                blockBufferOut: &blockBuffer)
        }
        guard createStatus == kCMBlockBufferNoErr, let bb = blockBuffer else { return }

        // Como usamos kCFAllocatorNull, precisamos copiar os bytes para um buffer
        // gerenciado pelo CMBlockBuffer e garantir que sobrevivam à chamada async.
        var managedBlock: CMBlockBuffer?
        let copyStatus = CMBlockBufferCreateContiguous(
            allocator: kCFAllocatorDefault,
            sourceBuffer: bb,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: kCMBlockBufferAlwaysCopyDataFlag,
            blockBufferOut: &managedBlock)
        guard copyStatus == kCMBlockBufferNoErr, let block = managedBlock else { return }

        // Timing: PTS em microssegundos -> CMTime (timescale 1_000_000).
        let pts = CMTime(value: frame.ptsMicros, timescale: 1_000_000)
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: pts,
                                        decodeTimeStamp: .invalid)

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = avcc.count
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: fmt,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer)
        guard sampleStatus == noErr, let sample = sampleBuffer else { return }

        // Decodifica (assíncrono; o callback entrega o pixel buffer).
        var flagsOut = VTDecodeInfoFlags()
        let decodeFlags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
        let decStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: decodeFlags,
            frameRefcon: nil,
            infoFlagsOut: &flagsOut)

        if decStatus != noErr {
            Log.decoder.error("DecodeFrame falhou status \(decStatus)")
        }
    }

    // MARK: - Teardown

    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        teardownLocked()
        formatDescription = nil
    }

    private func teardownLocked() {
        if let s = session {
            VTDecompressionSessionWaitForAsynchronousFrames(s)
            VTDecompressionSessionInvalidate(s)
        }
        session = nil
    }

    // Encaminha o frame decodificado vindo do callback C.
    fileprivate func handleDecodedImage(_ image: CVImageBuffer?, pts: CMTime) {
        guard let image = image else { return }
        onDecodedFrame?(image, pts)
    }
}

// MARK: - Callback C do VideoToolbox

/// Função C chamada pelo VideoToolbox quando um frame é decodificado.
private func decoderOutputCallback(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    presentationDuration: CMTime
) {
    guard status == noErr, let refCon = decompressionOutputRefCon else { return }
    let decoder = Unmanaged<H264Decoder>.fromOpaque(refCon).takeUnretainedValue()
    decoder.handleDecodedImage(imageBuffer, pts: presentationTimeStamp)
}
