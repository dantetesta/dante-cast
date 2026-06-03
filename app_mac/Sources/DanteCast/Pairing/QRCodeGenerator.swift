import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

/// Gera um QR code (NSImage) a partir de uma string/JSON usando CIQRCodeGenerator.
enum QRCodeGenerator {

    private static let context = CIContext()

    /// Gera um NSImage de QR para a string informada.
    /// `size` é o lado em pontos da imagem final (nítida, sem interpolação suave).
    static func generate(from string: String, size: CGFloat = 240) -> NSImage? {
        let data = Data(string.utf8)

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"   // ~15% de correção de erro

        guard let output = filter.outputImage else { return nil }

        // Escala o QR (que sai bem pequeno) até o tamanho desejado, sem suavizar.
        let scaleX = size / output.extent.width
        let scaleY = size / output.extent.height
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }

    /// Conveniência: gera o QR a partir de um PairingPayload (JSON compacto).
    static func generate(from payload: PairingPayload, size: CGFloat = 240) -> NSImage? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return generate(from: json, size: size)
    }
}
