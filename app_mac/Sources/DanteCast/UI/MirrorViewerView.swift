import SwiftUI

/// Visualizador principal: renderiza o vídeo + toolbar de controles grande e intuitiva.
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
        HStack(spacing: 6) {
            // Bloco de status (esquerda).
            VStack(alignment: .leading, spacing: 3) {
                StatusBadge(status: app.status)
                HStack(spacing: 8) {
                    if app.status == .streaming { LatencyView(latencyMs: app.latencyMs) }
                    if app.videoSize.width > 0 {
                        Label("\(Int(app.videoSize.width))×\(Int(app.videoSize.height))",
                              systemImage: "rectangle.ratio.9.to.16")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            // Grupo: visualização.
            ToolbarButton(title: "Tela cheia", systemImage: "arrow.up.left.and.arrow.down.right") {
                app.toggleFullscreen()
            }
            ToolbarButton(title: "No topo", systemImage: "pin",
                          isActive: app.isAlwaysOnTop) { app.toggleAlwaysOnTop() }
            ToolbarButton(title: "Girar", systemImage: "rotate.right") { app.rotateClockwise() }
            ToolbarButton(title: "Moldura", systemImage: "iphone",
                          isActive: app.settings.showDeviceFrame) {
                app.settings.showDeviceFrame.toggle()
                app.saveSettings()
            }

            groupDivider

            // Grupo: captura.
            ToolbarButton(title: "Captura", systemImage: "camera") { app.takeScreenshot() }
            ToolbarButton(title: app.isRecording ? "Parar" : "Gravar",
                          systemImage: app.isRecording ? "stop.circle.fill" : "record.circle",
                          isActive: app.isRecording, tint: .red) { app.toggleRecording() }

            groupDivider

            // Grupo: qualidade + desconectar.
            VStack(spacing: 2) {
                Picker("", selection: Binding(
                    get: { app.settings.quality },
                    set: { app.settings.quality = $0; app.saveSettings() })) {
                    ForEach(StreamQuality.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 92)
                Text("Qualidade").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .help("Qualidade do stream")

            ToolbarButton(title: "Desconectar", systemImage: "xmark.circle", tint: .red) {
                app.disconnectClient()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var groupDivider: some View {
        Divider().frame(height: 34).padding(.horizontal, 2)
    }

    // MARK: - Área de vídeo

    /// Proporção efetiva (considerando rotação) para a moldura.
    private var effectiveAspect: CGSize {
        let s = app.videoSize
        guard s.width > 0, s.height > 0 else { return CGSize(width: 9, height: 19.5) }
        return (app.rotation % 180 == 0) ? s : CGSize(width: s.height, height: s.width)
    }

    @ViewBuilder
    private var videoArea: some View {
        ZStack {
            backdrop

            if app.settings.showDeviceFrame && app.videoSize.width > 0 {
                DeviceFrameView(aspect: effectiveAspect) {
                    VideoRendererView(rotation: app.rotation) { app.attachRenderView($0) }
                }
            } else {
                VideoRendererView(rotation: app.rotation) { app.attachRenderView($0) }
            }

            overlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Fundo do palco: preto puro sem moldura; gradiente sutil com moldura.
    private var backdrop: some View {
        Group {
            if app.settings.showDeviceFrame {
                LinearGradient(colors: [Color(white: 0.10), Color(white: 0.03)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var overlay: some View {
        switch app.status {
        case .streaming:
            EmptyView()
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
                ProgressView().controlSize(.large).tint(.white)
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
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}
