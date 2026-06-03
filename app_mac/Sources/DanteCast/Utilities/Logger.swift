import Foundation
import os

/// Wrapper leve em torno do os.Logger para padronizar logs do app.
/// Cada subsistema usa uma categoria própria, facilitando o filtro no Console.app.
enum Log {
    private static let subsystem = "com.dantetesta.dantecast.mac"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let net = Logger(subsystem: subsystem, category: "network")
    static let decoder = Logger(subsystem: subsystem, category: "decoder")
    static let render = Logger(subsystem: subsystem, category: "render")
    static let record = Logger(subsystem: subsystem, category: "record")
    static let pairing = Logger(subsystem: subsystem, category: "pairing")
}
