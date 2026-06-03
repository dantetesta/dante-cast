import Foundation
import AppKit

/// Monta os dados de pareamento: gera token de sessão, resolve IP da LAN,
/// descobre o nome do Mac e produz o payload/QR.
final class PairingService {

    /// Resultado completo do pareamento atual.
    struct PairingInfo {
        var payload: PairingPayload
        var qrImage: NSImage?
        var jsonString: String
    }

    /// Gera um token aleatório curto e legível (base usada também no manual).
    static func generateToken() -> String {
        // 6 grupos hex -> 24 chars, suficientemente único e fácil de digitar parcialmente.
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// Constrói as informações de pareamento para a porta/token atuais.
    static func makePairingInfo(port: UInt16, token: String) -> PairingInfo {
        let ip = NetworkInterfaces.currentLANIPv4() ?? "0.0.0.0"
        let name = NetworkInterfaces.hostName()

        let payload = PairingPayload(v: 1,
                                     ip: ip,
                                     port: Int(port),
                                     token: token,
                                     name: name)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let json = (try? encoder.encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        let qr = QRCodeGenerator.generate(from: payload, size: 260)
        return PairingInfo(payload: payload, qrImage: qr, jsonString: json)
    }
}
