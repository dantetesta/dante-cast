import Foundation

/// Metadados de uma gravação .mov salva em disco.
struct Recording: Codable, Identifiable, Equatable {
    var id: String
    var sessionId: String
    var filePath: String
    var duration: Int   // segundos
    var createdAt: Date

    init(id: String = UUID().uuidString,
         sessionId: String,
         filePath: String,
         duration: Int = 0,
         createdAt: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.filePath = filePath
        self.duration = duration
        self.createdAt = createdAt
    }
}
