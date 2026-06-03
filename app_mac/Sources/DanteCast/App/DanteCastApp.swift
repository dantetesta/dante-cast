import SwiftUI
import AppKit

/// Ponto de entrada @main do SwiftUI App.
@main
struct DanteCastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 880, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Atalhos de menu úteis.
            CommandGroup(after: .toolbar) {
                Button("Tela Cheia") { appState.toggleFullscreen() }
                    .keyboardShortcut("f", modifiers: [.command, .control])
                Button(appState.isAlwaysOnTop ? "Desafixar Janela" : "Manter no Topo") {
                    appState.toggleAlwaysOnTop()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Ajuda do Dante Cast") { appState.screen = .help }
            }
        }
    }
}

/// AppDelegate para definir a política de ativação (.regular = app normal no Dock).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
