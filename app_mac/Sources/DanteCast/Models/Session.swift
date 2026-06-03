import Foundation

/// Sessão de espelhamento ativa entre o Mac (servidor) e o Android (cliente).
struct Session: Codable, Identifiable, Equatable {
    var id: String
    var deviceId: String
    var token: String
    var startedAt: Date?
    var endedAt: Date?
    var resolution: String
    var fps: Int
    var bitrate: Int
    var status: ConnectionStatus

    init(id: String = UUID().uuidString,
         deviceId: String,
         token: String,
         startedAt: Date? = nil,
         endedAt: Date? = nil,
         resolution: String = "",
         fps: Int = 0,
         bitrate: Int = 0,
         status: ConnectionStatus = .idle) {
        self.id = id
        self.deviceId = deviceId
        self.token = token
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.resolution = resolution
        self.fps = fps
        self.bitrate = bitrate
        self.status = status
    }
}
