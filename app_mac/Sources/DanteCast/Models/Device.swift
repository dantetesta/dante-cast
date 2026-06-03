import Foundation

/// Representa um dispositivo Android que se conectou (ou pode se conectar).
struct Device: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var ipAddress: String
    var lastConnectedAt: Date?
    var trusted: Bool

    init(id: String = UUID().uuidString,
         name: String,
         ipAddress: String,
         lastConnectedAt: Date? = nil,
         trusted: Bool = false) {
        self.id = id
        self.name = name
        self.ipAddress = ipAddress
        self.lastConnectedAt = lastConnectedAt
        self.trusted = trusted
    }
}
