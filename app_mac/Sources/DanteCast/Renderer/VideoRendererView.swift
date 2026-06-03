import SwiftUI
import AppKit
import AVFoundation
import CoreMedia
import CoreVideo

/// NSView que exibe frames via AVSampleBufferDisplayLayer.
/// Recebe CVPixelBuffers já decodificados, embrulha em CMSampleBuffer e enfileira.
final class SampleBufferRenderView: NSView {

    private var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    /// Rotação atual em graus (0/90/180/270) — aplicada via transform da camada.
    var rotationDegrees: Int = 0 { didSet { applyTransform() } }

    /// Cache do format description (recriar por frame é desperdício de CPU).
    private var cachedFormat: CMVideoFormatDescription?
    private var cachedDims: (Int, Int) = (0, 0)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        let l = AVSampleBufferDisplayLayer()
        l.videoGravity = .resizeAspect          // aspect-fit
        l.backgroundColor = NSColor.black.cgColor
        self.layer = l
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        applyTransform()
    }

    private func applyTransform() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        let radians = CGFloat(rotationDegrees) * .pi / 180
        displayLayer.setAffineTransform(CGAffineTransform(rotationAngle: radians))
        CATransaction.commit()
    }

    /// Enfileira um pixel buffer decodificado para exibição.
    func enqueue(pixelBuffer: CVPixelBuffer, pts: CMTime) {
        guard let sample = makeSampleBuffer(from: pixelBuffer, pts: pts) else { return }

        // Se a camada falhou, recria. (Pode acontecer ao reconfigurar.)
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        if displayLayer.isReadyForMoreMediaData {
            displayLayer.enqueue(sample)
        }
    }

    /// Limpa a tela (ao desconectar).
    func flush() {
        DispatchQueue.main.async { [weak self] in
            self?.displayLayer.flushAndRemoveImage()
        }
    }

    /// Constrói um CMSampleBuffer (com timing) a partir de um CVPixelBuffer.
    private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer, pts: CMTime) -> CMSampleBuffer? {
        // Reusa o format description enquanto as dimensões não mudarem.
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let fmt: CMVideoFormatDescription
        if let cached = cachedFormat, cachedDims == (w, h) {
            fmt = cached
        } else {
            var formatDesc: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDesc)
            guard status == noErr, let newFmt = formatDesc else { return nil }
            cachedFormat = newFmt
            cachedDims = (w, h)
            fmt = newFmt
        }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: pts.isValid ? pts : CMTime(value: 0, timescale: 1_000_000),
            decodeTimeStamp: .invalid)

        var sampleBuffer: CMSampleBuffer?
        let s = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fmt,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer)
        guard s == noErr, let sample = sampleBuffer else { return nil }

        // Exibe imediatamente (display ASAP) — não há clock de mídia aqui.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

/// Ponte SwiftUI -> SampleBufferRenderView.
/// O `coordinator` recebe a view criada para que o AppState possa enfileirar frames.
struct VideoRendererView: NSViewRepresentable {

    /// Rotação aplicada (graus).
    var rotation: Int
    /// Chamado quando a NSView é criada, expondo-a para enfileirar frames.
    var onMakeView: (SampleBufferRenderView) -> Void

    func makeNSView(context: Context) -> SampleBufferRenderView {
        let view = SampleBufferRenderView(frame: .zero)
        view.rotationDegrees = rotation
        onMakeView(view)
        return view
    }

    func updateNSView(_ nsView: SampleBufferRenderView, context: Context) {
        nsView.rotationDegrees = rotation
    }
}
