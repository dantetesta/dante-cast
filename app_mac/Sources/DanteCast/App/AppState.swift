import Foundation
import SwiftUI
import AppKit
import CoreVideo
import CoreMedia

/// Telas/abas principais navegáveis pela sidebar.
enum AppScreen: String, CaseIterable, Identifiable {
    case welcome = "Início"
    case pair = "Parear"
    case viewer = "Espelhar"
    case settings = "Ajustes"
    case help = "Ajuda"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .welcome:  return "house"
        case .pair:     return "qrcode"
        case .viewer:   return "play.rectangle"
        case .settings: return "gearshape"
        case .help:     return "questionmark.circle"
        }
    }
}

/// Coordenador central: liga MirrorServer -> H264Decoder -> Renderer -> Recorder.
/// Mantém todo o estado observável da UI. Roda no main actor.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Estado publicado para a UI

    @Published var screen: AppScreen = .welcome
    @Published var status: ConnectionStatus = .idle
    @Published var settings: StreamSettings = .default
    @Published var lastError: String?

    @Published var currentDevice: Device?
    @Published var currentSession: Session?

    @Published var latencyMs: Double = 0
    @Published var isRecording = false
    @Published var rotation: Int = 0                 // 0/90/180/270
    @Published var videoSize: CGSize = .zero         // resolução do stream atual
    @Published var isAlwaysOnTop = false

    /// Info de pareamento atual (QR + payload). nil quando o servidor está parado.
    @Published var pairing: PairingService.PairingInfo?

    // MARK: - Subsistemas

    private let server = MirrorServer()
    private let decoder = H264Decoder()
    private let recorder = ScreenRecorder()

    /// View de renderização (definida pela SwiftUI ao aparecer).
    private weak var renderView: SampleBufferRenderView?

    /// Último pixel buffer decodificado (para screenshot/gravação imediata).
    private var latestPixelBuffer: CVPixelBuffer?
    private let pixelLock = NSLock()

    private var sessionToken: String = ""

    init() {
        loadSettings()
        wireDecoder()
        wireServer()
    }

    // MARK: - Ligação dos subsistemas

    private func wireDecoder() {
        decoder.onDecodedFrame = { [weak self] pixelBuffer, pts in
            guard let self = self else { return }
            // Guarda o último frame (thread do decoder).
            self.pixelLock.lock()
            self.latestPixelBuffer = pixelBuffer
            self.pixelLock.unlock()

            // Renderiza no main.
            DispatchQueue.main.async {
                self.renderView?.enqueue(pixelBuffer: pixelBuffer, pts: pts)
            }
            // Alimenta a gravação (se ativa).
            self.recorder.append(pixelBuffer: pixelBuffer, pts: pts)
        }
        decoder.onError = { [weak self] message in
            DispatchQueue.main.async { self?.lastError = message }
        }
    }

    private func wireServer() {
        server.onStatusChange = { [weak self] status in
            guard let self = self else { return }
            self.status = status
            if status == .streaming || status == .connecting { self.screen = .viewer }
        }
        server.onError = { [weak self] message in
            self?.lastError = message
        }
        server.onHello = { [weak self] hello in
            guard let self = self else { return }
            let device = Device(id: hello.device.id,
                                name: hello.device.name,
                                ipAddress: self.currentDevice?.ipAddress ?? "",
                                lastConnectedAt: Date(),
                                trusted: true)
            self.currentDevice = device
            self.currentSession = Session(
                deviceId: device.id,
                token: self.sessionToken,
                startedAt: Date(),
                resolution: "",
                fps: self.settings.fps.rawValue,
                bitrate: self.settings.bitrate,
                status: .connecting)
            self.screen = .viewer
            self.lastError = nil
            Log.app.info("Dispositivo pareado: \(hello.device.name)")
        }
        server.onVideoConfig = { [weak self] config in
            guard let self = self else { return }
            self.decoder.configure(with: config)
            // Atualiza tamanho lógico (orientação pode sobrescrever).
            if config.width > 0 && config.height > 0 {
                self.videoSize = CGSize(width: Int(config.width), height: Int(config.height))
                self.currentSession?.resolution = "\(config.width)x\(config.height)"
            }
        }
        server.onVideoFrame = { [weak self] frame in
            self?.decoder.decode(frame: frame)
        }
        server.onOrientation = { [weak self] o in
            guard let self = self else { return }
            self.rotation = o.rotation
            if o.width > 0 && o.height > 0 {
                self.videoSize = CGSize(width: o.width, height: o.height)
            }
        }
        server.onPingRoundTrip = { [weak self] rtt in
            // Latência one-way aproximada = RTT/2.
            self?.latencyMs = rtt / 2.0
        }
        server.onClientDisconnected = { [weak self] in
            guard let self = self else { return }
            self.decoder.invalidate()
            self.renderView?.flush()
            self.currentSession?.endedAt = Date()
            self.currentSession?.status = .disconnected
            if self.isRecording { self.stopRecording() }
            self.latencyMs = 0
        }
    }

    // MARK: - Renderer hookup

    func attachRenderView(_ view: SampleBufferRenderView) {
        self.renderView = view
    }

    // MARK: - Ciclo do servidor

    /// Inicia o servidor, gera token + QR de pareamento.
    func startServer() {
        lastError = nil
        sessionToken = PairingService.generateToken()
        let info = PairingService.makePairingInfo(port: settings.port, token: sessionToken)
        pairing = info

        // Configura o que será anunciado no HELLO_ACK.
        server.macName = NetworkInterfaces.hostName()
        server.sessionId = UUID().uuidString
        server.ackSettings = HelloAck.AckSettings(
            width: settings.effectiveWidth,
            height: settings.effectiveHeight,
            fps: settings.fps.rawValue,
            bitrate: settings.bitrate,
            codec: "h264")

        server.start(port: settings.port, token: sessionToken)
        screen = .pair
    }

    /// Para tudo: servidor, decoder, gravação.
    func stopServer() {
        if isRecording { stopRecording() }
        server.stop()
        decoder.invalidate()
        renderView?.flush()
        pairing = nil
        status = .idle
        latencyMs = 0
        currentSession?.endedAt = Date()
    }

    /// Desconecta o cliente atual mas mantém o servidor escutando.
    func disconnectClient() {
        if isRecording { stopRecording() }
        server.disconnectClient()
    }

    // MARK: - Gravação

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard videoSize.width > 0, videoSize.height > 0 else {
            lastError = "Sem vídeo para gravar ainda."
            return
        }
        let folder = recordingsFolder()
        if recorder.start(in: folder, size: videoSize) != nil {
            isRecording = true
        } else {
            lastError = "Não foi possível iniciar a gravação."
        }
    }

    private func stopRecording() {
        recorder.stop { [weak self] _, _ in
            self?.isRecording = false
        }
    }

    // MARK: - Screenshot

    func takeScreenshot() {
        pixelLock.lock(); let buf = latestPixelBuffer; pixelLock.unlock()
        guard let buf = buf else {
            lastError = "Nenhum frame disponível para captura."
            return
        }
        let folder = recordingsFolder()
        if ScreenshotCapture.savePNG(from: buf, in: folder) == nil {
            lastError = "Falha ao salvar o screenshot."
        }
    }

    // MARK: - Rotação manual

    func rotateClockwise() {
        rotation = (rotation + 90) % 360
    }

    // MARK: - Janela: fullscreen / always-on-top

    func toggleFullscreen() {
        mainWindow?.toggleFullScreen(nil)
    }

    func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        mainWindow?.level = isAlwaysOnTop ? .floating : .normal
    }

    private var mainWindow: NSWindow? {
        NSApplication.shared.windows.first { $0.isVisible }
    }

    // MARK: - Pasta de gravações / screenshots

    func recordingsFolder() -> URL {
        if let path = settings.recordingFolderPath, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return movies.appendingPathComponent("DanteCast", isDirectory: true)
    }

    // MARK: - Persistência de settings (UserDefaults)

    private let settingsKey = "DanteCast.StreamSettings"

    func saveSettings() {
        settings.applyQualityPreset()
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
        // Atualiza o anúncio do servidor para a próxima conexão.
        server.ackSettings = HelloAck.AckSettings(
            width: settings.effectiveWidth,
            height: settings.effectiveHeight,
            fps: settings.fps.rawValue,
            bitrate: settings.bitrate,
            codec: "h264")
    }

    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let s = try? JSONDecoder().decode(StreamSettings.self, from: data) {
            settings = s
        }
    }

    // MARK: - Conveniências para UI

    var isServerRunning: Bool {
        switch status {
        case .idle, .error: return false
        default: return true
        }
    }
    var isConnected: Bool {
        status == .streaming || status == .connecting
    }
}
