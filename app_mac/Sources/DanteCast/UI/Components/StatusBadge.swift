import SwiftUI

/// Badge colorido que reflete o ConnectionStatus atual.
struct StatusBadge: View {
    let status: ConnectionStatus

    private var color: Color {
        switch status {
        case .idle:         return .gray
        case .listening:    return .blue
        case .connecting:   return .orange
        case .streaming:    return .green
        case .disconnected: return .gray
        case .error:        return .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                // Pulsa suavemente quando ativo.
                .opacity(status == .streaming || status == .listening ? 1 : 0.7)
            Text(status.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}
