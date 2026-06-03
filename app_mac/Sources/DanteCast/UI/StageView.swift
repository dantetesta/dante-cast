import SwiftUI
import AppKit

/// Modo Flutuante/Palco: APENAS a moldura fina do celular com o vídeo,
/// sobre um fundo TRANSPARENTE (a janela é clear/non-opaque). Arrastável pelo
/// corpo, redimensionável mantendo a proporção do vídeo (max zoom).
///
/// Um pequeno painel de controles aparece ao passar o mouse (hover) e some sozinho.
struct StageView: View {
    @EnvironmentObject var app: AppState
    @State private var showControls = false

    /// Proporção efetiva (considera o override manual de rotação).
    private var effectiveAspect: CGSize {
        let s = app.videoSize
        guard s.width > 0, s.height > 0 else { return CGSize(width: 9, height: 19.5) }
        return (app.rotation % 180 == 0) ? s : CGSize(width: s.height, height: s.width)
    }

    var body: some View {
        ZStack {
            // Fundo CLARO/transparente: nada opaco atrás da moldura (é o que faz "flutuar").
            Color.clear

            if app.videoSize.width > 0 {
                DeviceFrameView(aspect: effectiveAspect) {
                    VideoRendererView(rotation: app.rotation, videoSize: app.videoSize) {
                        app.attachRenderView($0)
                    }
                }
            } else {
                // Sem vídeo ainda: placeholder discreto.
                VStack(spacing: 10) {
                    Image(systemName: "iphone").font(.system(size: 40))
                    Text("Aguardando vídeo…").font(.callout)
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(28)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            }

            // Overlay de controles (auto-hide no hover).
            if showControls {
                controls
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { showControls = hovering }
        }
        // Esc sai do palco (botão invisível com atalho).
        .background(
            Button("") { app.setStageMode(false) }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
        )
        // Sincroniza a proporção da janela sempre que o vídeo/rotação mudar.
        .onAppear { app.updateStageAspect() }
        .onChange(of: app.videoSize) { _ in app.updateStageAspect() }
        .onChange(of: app.rotation) { _ in app.updateStageAspect() }
    }

    // MARK: - Controles flutuantes

    private var controls: some View {
        VStack {
            HStack(spacing: 14) {
                stageButton(app.isRecording ? "stop.circle.fill" : "record.circle",
                            tint: app.isRecording ? .red : .white,
                            help: app.isRecording ? "Parar gravação" : "Gravar") {
                    app.toggleRecording()
                }
                stageButton("camera", help: "Captura de tela") { app.takeScreenshot() }

                if app.hasDeviceAudio { volumeControl }

                stageButton("rotate.right", help: "Girar") { app.rotateClockwise() }
                stageButton("xmark.circle", tint: .white, help: "Sair do modo flutuante") {
                    app.setStageMode(false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .padding(.top, 14)

            Spacer()
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 6) {
            Button { app.toggleMute() } label: {
                Image(systemName: app.isMuted || app.volume == 0
                      ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            Slider(value: Binding(get: { app.volume }, set: { app.setVolume($0) }),
                   in: 0...1)
                .frame(width: 80)
        }
        .foregroundStyle(.white)
        .help("Volume do áudio do dispositivo")
    }

    private func stageButton(_ system: String, tint: Color = .white,
                             help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
