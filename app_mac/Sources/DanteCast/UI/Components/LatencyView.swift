import SwiftUI

/// Mostra a latência estimada (ms) com cor de acordo com a faixa.
struct LatencyView: View {
    let latencyMs: Double

    private var color: Color {
        switch latencyMs {
        case ..<60:   return .green
        case ..<120:  return .yellow
        default:      return .red
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.caption2)
                .foregroundStyle(color)
            Text(latencyMs > 0 ? "\(Int(latencyMs)) ms" : "— ms")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .help("Latência estimada (one-way)")
    }
}
