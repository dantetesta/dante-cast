import SwiftUI

/// Botão de toolbar grande e intuitivo: ícone + rótulo, área de toque ampla,
/// feedback de hover e estado ativo (preenche o ícone + destaque de fundo).
struct ToolbarButton: View {
    let title: String
    let systemImage: String
    var isActive: Bool = false
    var tint: Color = .accentColor
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .symbolVariant(isActive ? .fill : .none)
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 60, height: 48)
            .foregroundStyle(isActive ? tint : (hovering ? Color.primary : Color.secondary))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? tint.opacity(0.16)
                                   : (hovering ? Color.primary.opacity(0.08) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title)
    }
}
