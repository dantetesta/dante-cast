import SwiftUI

/// View raiz com navegação por sidebar entre as telas principais.
struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            if app.stageMode {
                // Modo Flutuante/Palco: só a moldura do celular sobre fundo transparente.
                StageView()
            } else {
                normalLayout
            }
        }
        // Skin: segue o sistema, ou força claro/escuro conforme os Ajustes.
        .preferredColorScheme(app.settings.appearance.colorScheme)
    }

    /// Layout normal: sidebar + detail + banner de erro.
    private var normalLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(minWidth: 640, minHeight: 480)
        }
        .frame(minWidth: 880, minHeight: 600)
        // Banner de erro global (não bloqueante).
        .overlay(alignment: .bottom) {
            if let error = app.lastError {
                errorBanner(error)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: app.lastError)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $app.screen) {
            Section {
                ForEach(AppScreen.allCases) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.systemImage)
                    }
                }
            }

            Section("Status") {
                StatusBadge(status: app.status)
                if app.isConnected, let device = app.currentDevice {
                    Label(device.name, systemImage: "iphone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if app.status == .streaming {
                    LatencyView(latencyMs: app.latencyMs)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .navigationTitle("Dante Cast")
        .safeAreaInset(edge: .bottom) {
            if app.isServerRunning {
                Button(role: .destructive) {
                    app.stopServer()
                    app.screen = .welcome
                } label: {
                    Label("Parar Servidor", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .padding(8)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch app.screen {
        case .welcome:  WelcomeView()
        case .pair:     PairDeviceView()
        case .viewer:   MirrorViewerView()
        case .settings: SettingsView()
        case .help:     HelpView()
        }
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer()
            Button {
                app.lastError = nil
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
        .padding(16)
        .frame(maxWidth: 520)
    }
}
