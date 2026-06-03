import SwiftUI

/// Moldura/skin de smartphone ao redor do conteúdo (o vídeo espelhado).
/// Desenha um corpo escuro com brilho metálico, cantos arredondados e uma
/// "dynamic island" — dando a sensação de um celular real na tela do Mac.
///
/// O conteúdo é ajustado por aspecto (`aspect`) e clipado nos cantos internos.
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

    // Espessura da borda e raios proporcionais ao formato.
    private var bezel: CGFloat { isPortrait ? 12 : 12 }
    private var innerCorner: CGFloat { isPortrait ? 30 : 26 }
    private var outerCorner: CGFloat { innerCorner + bezel }

    var body: some View {
        content
            .aspectRatio(ratio, contentMode: .fit)
            // Cantos internos da "tela".
            .clipShape(RoundedRectangle(cornerRadius: innerCorner, style: .continuous))
            // Dynamic island / câmera sobre a tela.
            .overlay(alignment: isPortrait ? .top : .leading) { island }
            // Borda interna sutil para separar tela do corpo.
            .padding(bezel)
            // Corpo do aparelho (a "moldura").
            .background(
                RoundedRectangle(cornerRadius: outerCorner, style: .continuous)
                    .fill(bodyGradient)
            )
            // Brilho metálico nas bordas.
            .overlay(
                RoundedRectangle(cornerRadius: outerCorner, style: .continuous)
                    .strokeBorder(edgeGradient, lineWidth: 1.5)
            )
            // Botões laterais (volume / power) — detalhe sutil.
            .overlay(alignment: isPortrait ? .trailing : .top) { sideButtons }
            .shadow(color: .black.opacity(0.55), radius: 28, x: 0, y: 14)
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detalhes

    private var island: some View {
        Group {
            if isPortrait {
                Capsule(style: .continuous)
                    .fill(Color.black)
                    .frame(width: 96, height: 26)
                    .padding(.top, 10)
            } else {
                Capsule(style: .continuous)
                    .fill(Color.black)
                    .frame(width: 26, height: 96)
                    .padding(.leading, 10)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 2)
    }

    private var sideButtons: some View {
        Group {
            if isPortrait {
                VStack(spacing: 10) {
                    Capsule().frame(width: 3, height: 56)
                    Capsule().frame(width: 3, height: 28)
                }
                .foregroundStyle(.black.opacity(0.55))
                .offset(x: 1.5)
                .padding(.top, 120)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                HStack(spacing: 10) {
                    Capsule().frame(width: 56, height: 3)
                    Capsule().frame(width: 28, height: 3)
                }
                .foregroundStyle(.black.opacity(0.55))
                .offset(y: 1.5)
                .padding(.leading, 120)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var bodyGradient: LinearGradient {
        LinearGradient(
            colors: [Color(white: 0.16), Color(white: 0.07)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var edgeGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.35), Color.white.opacity(0.04), Color.white.opacity(0.18)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
