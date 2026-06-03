import Foundation

/// Estados do ciclo de vida da conexão/streaming.
/// idle        -> servidor parado, nada acontecendo
/// listening   -> servidor no ar aguardando o Android escanear o QR
/// connecting  -> cliente conectou TCP, fazendo handshake (HELLO)
/// streaming   -> recebendo frames de vídeo ativamente
/// disconnected-> cliente encerrou/caiu
/// error       -> falha (porta ocupada, token inválido, etc.)
enum ConnectionStatus: String, Codable, Equatable {
    case idle
    case listening
    case connecting
    case streaming
    case disconnected
    case error

    /// Texto curto para a interface.
    var displayText: String {
        switch self {
        case .idle:         return "Parado"
        case .listening:    return "Aguardando dispositivo"
        case .connecting:   return "Conectando…"
        case .streaming:    return "Transmitindo"
        case .disconnected: return "Desconectado"
        case .error:        return "Erro"
        }
    }
}
