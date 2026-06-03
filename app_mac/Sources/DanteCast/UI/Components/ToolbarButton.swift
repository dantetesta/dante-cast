import SwiftUI

/// Botão de toolbar compacto com ícone + label opcional e estado ativo.
struct ToolbarButton: View {
    let title: String
    let systemImage: String
    var isActive: Bool = false
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isActive ? tint : Color.primary)
        .background(isActive ? tint.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .help(title)
    }
}
