import SwiftUI
import AppKit

/// Ajustes: qualidade, fps, resolução, pasta de gravação, porta.
struct SettingsView: View {
    @EnvironmentObject var app: AppState

    @State private var portText: String = ""

    var body: some View {
        Form {
            Section("Vídeo") {
                Picker("Qualidade", selection: binding(\.quality)) {
                    ForEach(StreamQuality.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Resolução", selection: binding(\.resolution)) {
                    ForEach(StreamResolution.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Taxa de quadros", selection: binding(\.fps)) {
                    ForEach(StreamFPS.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Bitrate") {
                    Text("\(app.settings.bitrate / 1_000_000) Mbps")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Servidor") {
                HStack {
                    Text("Porta TCP")
                    Spacer()
                    TextField("7843", text: $portText)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .onSubmit(commitPort)
                }
                if app.isServerRunning {
                    Label("Reinicie o servidor para aplicar a nova porta.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Gravações e Capturas") {
                HStack {
                    Text("Pasta")
                    Spacer()
                    Text(folderDisplay)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Escolher…") { chooseFolder() }
                }
                Button("Abrir pasta no Finder") {
                    NSWorkspace.shared.open(app.recordingsFolder())
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ajustes")
        .onAppear { portText = String(app.settings.port) }
    }

    // MARK: - Helpers

    private var folderDisplay: String {
        app.settings.recordingFolderPath ?? app.recordingsFolder().path
    }

    /// Binding genérico que persiste a settings ao mudar.
    private func binding<T>(_ keyPath: WritableKeyPath<StreamSettings, T>) -> Binding<T> {
        Binding(
            get: { app.settings[keyPath: keyPath] },
            set: { app.settings[keyPath: keyPath] = $0; app.saveSettings() }
        )
    }

    private func commitPort() {
        guard let value = UInt16(portText), value > 0 else {
            portText = String(app.settings.port)
            return
        }
        app.settings.port = value
        app.saveSettings()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Selecionar"
        if panel.runModal() == .OK, let url = panel.url {
            app.settings.recordingFolderPath = url.path
            app.saveSettings()
        }
    }
}
