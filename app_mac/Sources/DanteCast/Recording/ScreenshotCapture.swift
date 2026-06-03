import Foundation
import AppKit
import CoreImage
import CoreVideo

/// Captura um screenshot a partir do último CVPixelBuffer decodificado.
enum ScreenshotCapture {

    private static let ciContext = CIContext()

    /// Converte um CVPixelBuffer em NSImage.
    static func image(from pixelBuffer: CVPixelBuffer) -> NSImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = ci.extent
        guard let cg = ciContext.createCGImage(ci, from: rect) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: rect.width, height: rect.height))
    }

    /// Salva o pixel buffer como PNG na pasta indicada. Retorna a URL salva.
    @discardableResult
    static func savePNG(from pixelBuffer: CVPixelBuffer, in folder: URL) -> URL? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = folder.appendingPathComponent("DanteCast_\(formatter.string(from: Date())).png")

        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        do {
            try data.write(to: url)
            Log.record.info("Screenshot salvo: \(url.lastPathComponent)")
            return url
        } catch {
            Log.record.error("Falha ao salvar screenshot: \(error.localizedDescription)")
            return nil
        }
    }
}
