import SwiftUI

/// Moldura MINIMALISTA de smartphone ao redor do conteúdo (o vídeo espelhado).
///
/// Design: um aro fino (~6–8pt) escuro com cantos arredondados e um brilho
/// metálico sutil. NADA fora do aro (sem corpo grosso, sem dynamic island,
/// sem botões laterais, sem sombra pesada) — fundo TRANSPARENTE para "flutuar".
///
/// O conteúdo é ajustado por aspecto (`aspect`) e clipado nos cantos internos,
/// preenchendo a área disponível no maior tamanho possível (max zoom).
struct DeviceFrameView<Content: View>: View {
    /// Proporção do vídeo (largura × altura) já considerando a rotação.
    let aspect: CGSize
    private let content: Content

    init(aspect: CGSize, @ViewBuilder content: () -> Content) {
        self.aspect = aspect
        self.content = content()
    }

    private var ratio: CGFloat {
        guard aspect.width > 0, aspect.height > 0 else { return 9.0 / 19.5 }
        return aspect.width / aspect.height
    }
    private var isPortrait: Bool { ratio < 1 }

    // Aro fino e cantos arredondados proporcionais ao formato.
    private var bezel: CGFloat { 7 }
    private var innerCorner: CGFloat { isPortrait ? 26 : 22 }
    private var outerCorner: CGFloat { innerCorner + bezel }

    var body: some View {
        content
            // Cantos internos da "tela" (clipa o vídeo).
            .aspectRatio(ratio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: innerCorner, style: .continuous))
            // Aro fino escuro (a "moldura"): preenche só a espessura da borda.
            .padding(bezel)
            .background(
                RoundedRectangle(cornerRadius: outerCorner, style: .continuous)
                    .fill(bezelGradient)
            )
            // Brilho metálico sutil na borda externa.
            .overlay(
                RoundedRectangle(cornerRadius: outerCorner, style: .continuous)
                    .strokeBorder(edgeGradient, lineWidth: 1)
            )
            // Sombra MUITO leve só para destacar do fundo transparente.
            .shadow(color: .black.opacity(0.30), radius: 10, x: 0, y: 4)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Estilo

    private var bezelGradient: LinearGradient {
        LinearGradient(
            colors: [Color(white: 0.14), Color(white: 0.05)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var edgeGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.30), Color.white.opacity(0.03), Color.white.opacity(0.14)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
