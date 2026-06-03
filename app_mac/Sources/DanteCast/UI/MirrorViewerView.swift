import SwiftUI

/// Visualizador principal: renderiza o vídeo + toolbar de controles.
struct MirrorViewerView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            videoArea
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            StatusBadge(status: app.status)
            LatencyView(latencyMs: app.latencyMs)
            if app.videoSize.width > 0 {
                Text("\(Int(app.videoSize.width))×\(Int(app.videoSize.height))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Controles de visualização.
            ToolbarButton(title: "Tela cheia", systemImage: "arrow.up.left.and.arrow.down.right") {
                app.toggleFullscreen()
            }
            ToolbarButton(title: "Sempre no topo", systemImage: "pin",
                          isActive: app.isAlwaysOnTop) {
                app.toggleAlwaysOnTop()
            }
            ToolbarButton(title: "Girar", systemImage: "rotate.right") {
                app.rotateClockwise()
            }

            Divider().frame(height: 18)

            // Captura.
            ToolbarButton(title: "Captura de tela", systemImage: "camera") {
                app.takeScreenshot()
            }
            ToolbarButton(title: app.isRecording ? "Parar gravação" : "Gravar",
                          systemImage: app.isRecording ? "stop.circle.fill" : "record.circle",
                          isActive: app.isRecording,
                          tint: .red) {
                app.toggleRecording()
            }

            Divider().frame(height: 18)

            // Qualidade rápida.
            Picker("", selection: Binding(
                get: { app.settings.quality },
                set: { app.settings.quality = $0; app.saveSettings() })) {
                ForEach(StreamQuality.allCases) { q in
                    Text(q.rawValue).tag(q)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .help("Qualidade")

            ToolbarButton(title: "Desconectar", systemImage: "xmark.circle", tint: .red) {
                app.disconnectClient()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: - Área de vídeo

    @ViewBuilder
    private var videoArea: some View {
        ZStack {
            Color.black

            // A view de render fica sempre montada para receber frames.
            VideoRendererView(rotation: app.rotation) { view in
                app.attachRenderView(view)
            }

            // Overlays de estado (sobre o vídeo).
            overlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var overlay: some View {
        switch app.status {
        case .streaming:
            EmptyView() // vídeo ocupa tudo
        case .connecting:
            stateOverlay(icon: "antenna.radiowaves.left.and.right",
                         title: "Conectando…",
                         subtitle: "Aguardando o início do stream.",
                         showSpinner: true)
        case .listening:
            stateOverlay(icon: "qrcode.viewfinder",
                         title: "Aguardando dispositivo",
                         subtitle: "Escaneie o QR no app Android para iniciar.")
        case .disconnected:
            stateOverlay(icon: "iphone.slash",
                         title: "Dispositivo desconectado",
                         subtitle: "Reconecte pelo app Android.")
        case .error:
            stateOverlay(icon: "exclamationmark.triangle.fill",
                         title: "Erro de conexão",
                         subtitle: app.lastError ?? "Falha desconhecida.",
                         tint: .red)
        case .idle:
            stateOverlay(icon: "play.rectangle",
                         title: "Nenhuma sessão",
                         subtitle: "Inicie o servidor para começar.")
        }
    }

    private func stateOverlay(icon: String, title: String, subtitle: String,
                              showSpinner: Bool = false, tint: Color = .white) -> some View {
        VStack(spacing: 12) {
            if showSpinner {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(tint.opacity(0.9))
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }
}
