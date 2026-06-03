import Foundation
import SwiftUI

/// Qualidade desejada do stream. Cada nível mapeia para um bitrate sugerido.
enum StreamQuality: String, Codable, CaseIterable, Identifiable {
    case low = "Baixa"
    case medium = "Média"
    case high = "Alta"

    var id: String { rawValue }

    /// Bitrate sugerido (bps) por nível de qualidade.
    /// "Alta" sobe para ~18 Mbps para 60fps mais suave.
    var suggestedBitrate: Int {
        switch self {
        case .low:    return 2_000_000
        case .medium: return 8_000_000
        case .high:   return 18_000_000
        }
    }
}

/// Resolução alvo enviada ao Android no HELLO_ACK.
enum StreamResolution: String, Codable, CaseIterable, Identifiable {
    case hd720 = "720p"
    case hd1080 = "1080p"
    case native = "Nativa"

    var id: String { rawValue }

    /// Dimensões (largura, altura) sugeridas. `native` = 0,0 -> deixa o device decidir.
    var dimensions: (width: Int, height: Int) {
        switch self {
        case .hd720:  return (1280, 720)
        case .hd1080: return (1920, 1080)
        case .native: return (0, 0)
        }
    }
}

/// FPS alvo do stream.
enum StreamFPS: Int, Codable, CaseIterable, Identifiable {
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
    var label: String { "\(rawValue) fps" }
}

/// Aparência da interface (skin): segue o sistema, ou força claro/escuro.
enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system = "Sistema"
    case light = "Claro"
    case dark = "Escuro"

    var id: String { rawValue }

    /// ColorScheme correspondente para `.preferredColorScheme` (nil = segue o sistema).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }
}

/// Configurações de stream persistidas e enviadas ao Android.
struct StreamSettings: Codable, Equatable {
    var quality: StreamQuality
    var resolution: StreamResolution
    var fps: StreamFPS
    var bitrate: Int          // bps; pode ser ajustado manualmente
    var port: UInt16          // porta TCP do servidor
    var recordingFolderPath: String?  // pasta onde gravações/screenshots são salvos
    var appearance: AppAppearance = .system   // skin claro/escuro/sistema
    var recordAudio: Bool = false             // incluir áudio do microfone na gravação
    var showDeviceFrame: Bool = true          // moldura de smartphone no viewer
    var useManualBitrate: Bool = false        // se true, `bitrate` é manual (ignora preset)

    /// Limites do bitrate manual (bps): 2–20 Mbps.
    static let minBitrate = 2_000_000
    static let maxBitrate = 20_000_000

    /// Preset padrão equilibrado.
    static let `default` = StreamSettings(
        quality: .medium,
        resolution: .hd1080,
        fps: .fps30,
        bitrate: StreamQuality.medium.suggestedBitrate,
        port: 7843,
        recordingFolderPath: nil,
        appearance: .system,
        recordAudio: false,
        showDeviceFrame: true,
        useManualBitrate: false
    )

    /// Aplica o bitrate do preset de qualidade — A MENOS que o usuário tenha
    /// fixado um bitrate manual (que sobrepõe o preset no HELLO_ACK).
    mutating func applyQualityPreset() {
        if !useManualBitrate {
            bitrate = quality.suggestedBitrate
        } else {
            bitrate = max(Self.minBitrate, min(Self.maxBitrate, bitrate))
        }
    }

    /// Largura efetiva a anunciar (0 = nativa).
    var effectiveWidth: Int { resolution.dimensions.width }
    var effectiveHeight: Int { resolution.dimensions.height }
}
