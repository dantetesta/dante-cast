import Foundation

/// Parser incremental e bufferizado: recebe pedaços arbitrários de bytes do
/// stream TCP e devolve mensagens DCWP completas (length-prefixed).
///
/// O TCP não preserva fronteiras de mensagem, então acumulamos bytes em um
/// buffer interno e só emitimos quando há header (12B) + payload completos.
final class MessageReader {

    private var buffer = Data()
    /// Cursor de leitura: índice (relativo a buffer.startIndex) do próximo byte não consumido.
    /// Evita `removeSubrange` pela frente (O(n) por mensagem). Compactamos só de vez em quando.
    private var readOffset = 0

    /// Acrescenta bytes recém-chegados ao buffer interno.
    func append(_ data: Data) {
        buffer.append(data)
    }

    /// Extrai todas as mensagens completas atualmente disponíveis no buffer.
    /// Lança ParseError se encontrar um header inválido (conexão deve cair).
    func drain() throws -> [DCWP.Message] {
        var messages: [DCWP.Message] = []
        let base = buffer.startIndex

        while true {
            let available = buffer.count - readOffset
            // Precisa de pelo menos um header completo.
            guard available >= DCWP.headerSize else { break }

            let start = base + readOffset
            let header: (type: DCWP.MessageType, flags: UInt16, payloadLength: UInt32)
            do {
                header = try DCWP.parseHeader(buffer, at: start)
            } catch {
                // Header corrompido: propaga para derrubar a conexão.
                throw error
            }

            let total = DCWP.headerSize + Int(header.payloadLength)
            // Ainda não chegou o payload inteiro -> espera mais bytes.
            guard available >= total else { break }

            let payloadStart = start + DCWP.headerSize
            let payloadEnd = start + total
            let payload = buffer.subdata(in: payloadStart..<payloadEnd)

            messages.append(DCWP.Message(type: header.type,
                                         flags: header.flags,
                                         payload: payload))

            // Apenas avança o cursor — sem mover bytes.
            readOffset += total
        }

        // Compacta quando já consumimos bastante (evita crescimento ilimitado do buffer),
        // mas não a cada mensagem (mantém amortizado O(1)).
        if readOffset > 0 && (readOffset == buffer.count || readOffset >= 1 << 20) {
            if readOffset >= buffer.count {
                buffer.removeAll(keepingCapacity: true)
            } else {
                buffer.removeSubrange(base..<(base + readOffset))
            }
            readOffset = 0
        }

        return messages
    }

    /// Limpa todo o estado (ao desconectar).
    func reset() {
        buffer.removeAll(keepingCapacity: false)
        readOffset = 0
    }
}
