import Foundation

/// Parser incremental e bufferizado: recebe pedaços arbitrários de bytes do
/// stream TCP e devolve mensagens DCWP completas (length-prefixed).
///
/// O TCP não preserva fronteiras de mensagem, então acumulamos bytes em um
/// buffer interno e só emitimos quando há header (12B) + payload completos.
final class MessageReader {

    private var buffer = Data()

    /// Acrescenta bytes recém-chegados ao buffer interno.
    func append(_ data: Data) {
        buffer.append(data)
    }

    /// Extrai todas as mensagens completas atualmente disponíveis no buffer.
    /// Lança ParseError se encontrar um header inválido (conexão deve cair).
    func drain() throws -> [DCWP.Message] {
        var messages: [DCWP.Message] = []

        while true {
            // Precisa de pelo menos um header completo.
            guard buffer.count >= DCWP.headerSize else { break }

            // O Data pode ter startIndex != 0 após subdatas; normalizamos lendo
            // sempre a partir do startIndex atual.
            let start = buffer.startIndex
            let header: (type: DCWP.MessageType, flags: UInt16, payloadLength: UInt32)
            do {
                header = try DCWP.parseHeader(buffer, at: start)
            } catch {
                // Header corrompido: propaga para derrubar a conexão.
                throw error
            }

            let total = DCWP.headerSize + Int(header.payloadLength)
            // Ainda não chegou o payload inteiro -> espera mais bytes.
            guard buffer.count >= total else { break }

            let payloadStart = start + DCWP.headerSize
            let payloadEnd = start + total
            let payload = buffer.subdata(in: payloadStart..<payloadEnd)

            messages.append(DCWP.Message(type: header.type,
                                         flags: header.flags,
                                         payload: payload))

            // Remove a mensagem consumida do início do buffer.
            buffer.removeSubrange(start..<payloadEnd)
        }

        return messages
    }

    /// Limpa todo o estado (ao desconectar).
    func reset() {
        buffer.removeAll(keepingCapacity: false)
    }
}
