import Foundation

// MARK: - DCWP v1 — Dante Cast Wire Protocol
//
// Fonte única de verdade para o framing entre Mac (servidor) e Android (cliente).
// TODOS os inteiros multi-byte são BIG-ENDIAN (network order).
//
// Cada mensagem = HEADER de 12 bytes + payload:
//   bytes 0..3  : magic ASCII "DCWP" = 0x44,0x43,0x57,0x50
//   byte  4     : version = 0x01
//   byte  5     : type
//   bytes 6..7  : flags  uint16 (reservado = 0)
//   bytes 8..11 : payloadLength uint32 (rejeita > 16 MiB)
//
// Esta implementação precisa casar BYTE A BYTE com o lado Android.

enum DCWP {

    /// Magic "DCWP".
    static let magic: [UInt8] = [0x44, 0x43, 0x57, 0x50]
    static let version: UInt8 = 0x01
    static let headerSize = 12
    /// Limite de payload aceito: 16 MiB.
    static let maxPayload: UInt32 = 16 * 1024 * 1024

    /// Tipos de mensagem.
    enum MessageType: UInt8 {
        case hello        = 0x01  // A→M  JSON
        case helloAck     = 0x02  // M→A  JSON
        case videoConfig  = 0x10  // A→M  binário (SPS/PPS)
        case videoFrame   = 0x11  // A→M  binário (access unit)
        case orientation  = 0x20  // A→M  JSON
        case ping         = 0x30  // bin 8B
        case pong         = 0x31  // bin 8B
        case streamStop   = 0x40  // vazio
        case bye          = 0x41  // vazio
        case error        = 0x42  // JSON
    }

    /// Uma mensagem DCWP completa (já desmembrada do stream).
    struct Message {
        var type: MessageType
        var flags: UInt16
        var payload: Data

        init(type: MessageType, flags: UInt16 = 0, payload: Data = Data()) {
            self.type = type
            self.flags = flags
            self.payload = payload
        }

        /// Serializa header + payload prontos para envio na rede.
        func encoded() -> Data {
            var out = Data(capacity: DCWP.headerSize + payload.count)
            out.append(contentsOf: DCWP.magic)
            out.append(DCWP.version)
            out.append(type.rawValue)
            out.appendBE(flags)
            out.appendBE(UInt32(payload.count))
            out.append(payload)
            return out
        }
    }

    /// Erros de parsing do protocolo.
    enum ParseError: Error {
        case badMagic
        case badVersion(UInt8)
        case unknownType(UInt8)
        case payloadTooLarge(UInt32)
    }

    // MARK: - Decode de header
    //
    /// Tenta ler um header de 12 bytes a partir de `data` no offset informado.
    /// Retorna (type, flags, payloadLength) ou lança erro. Não consome bytes.
    static func parseHeader(_ data: Data, at offset: Int) throws
        -> (type: MessageType, flags: UInt16, payloadLength: UInt32) {

        // Confere magic.
        for i in 0..<4 where data[offset + i] != magic[i] {
            throw ParseError.badMagic
        }
        let ver = data[offset + 4]
        guard ver == version else { throw ParseError.badVersion(ver) }

        let rawType = data[offset + 5]
        guard let type = MessageType(rawValue: rawType) else {
            throw ParseError.unknownType(rawType)
        }

        let flags = data.readBE(UInt16.self, at: offset + 6)
        let length = data.readBE(UInt32.self, at: offset + 8)
        guard length <= maxPayload else { throw ParseError.payloadTooLarge(length) }

        return (type, flags, length)
    }

    // MARK: - Builders convenientes (M→A)

    static func helloAck(_ json: HelloAck) -> Message {
        Message(type: .helloAck, payload: (try? JSONEncoder().encode(json)) ?? Data())
    }
    static func pong(echo nanos: Int64) -> Message {
        var p = Data(); p.appendBE(nanos)
        return Message(type: .pong, payload: p)
    }
    static func errorMsg(_ json: ErrorMsg) -> Message {
        Message(type: .error, payload: (try? JSONEncoder().encode(json)) ?? Data())
    }
}

// MARK: - Payloads JSON

/// HELLO (A→M).
struct Hello: Codable {
    struct DeviceInfo: Codable {
        var id: String
        var name: String
        var model: String
        var osVersion: String
    }
    struct Capabilities: Codable {
        var maxWidth: Int
        var maxHeight: Int
        var fpsOptions: [Int]
    }
    var protocolVersion: Int
    var token: String
    var device: DeviceInfo
    var capabilities: Capabilities
}

/// HELLO_ACK (M→A).
struct HelloAck: Codable {
    struct AckSettings: Codable {
        var width: Int
        var height: Int
        var fps: Int
        var bitrate: Int
        var codec: String   // "h264"
    }
    var accepted: Bool
    var reason: String
    var macName: String
    var sessionId: String
    var settings: AckSettings
}

/// ORIENTATION (A→M).
struct Orientation: Codable {
    var width: Int
    var height: Int
    var rotation: Int   // 0|90|180|270
}

/// ERROR (A→M ou M→A).
struct ErrorMsg: Codable {
    var code: String
    var message: String
}

/// Payload do QR de pareamento: {"v":1,"ip","port","token","name"}.
struct PairingPayload: Codable {
    var v: Int
    var ip: String
    var port: Int
    var token: String
    var name: String
}

// MARK: - Sub-headers binários

/// VIDEO_CONFIG: [width u16][height u16][fps u16][flags u16] + SPS/PPS Annex-B.
struct VideoConfigPayload {
    var width: UInt16
    var height: UInt16
    var fps: UInt16
    var flags: UInt16
    var annexB: Data    // SPS + PPS em Annex-B

    static let subHeaderSize = 8

    /// Decodifica a partir do payload bruto da mensagem VIDEO_CONFIG.
    static func decode(_ payload: Data) -> VideoConfigPayload? {
        guard payload.count >= subHeaderSize else { return nil }
        let base = payload.startIndex
        let w = payload.readBE(UInt16.self, at: base + 0)
        let h = payload.readBE(UInt16.self, at: base + 2)
        let f = payload.readBE(UInt16.self, at: base + 4)
        let fl = payload.readBE(UInt16.self, at: base + 6)
        let annex = payload.subdata(in: (base + subHeaderSize)..<payload.endIndex)
        return VideoConfigPayload(width: w, height: h, fps: f, flags: fl, annexB: annex)
    }
}

/// VIDEO_FRAME: [ptsMicros i64][flags u8 (bit0=keyframe)][reserved 3B] + access unit Annex-B.
struct VideoFramePayload {
    var ptsMicros: Int64
    var isKeyframe: Bool
    var annexB: Data

    static let subHeaderSize = 12  // 8 (pts) + 1 (flags) + 3 (reserved)

    static func decode(_ payload: Data) -> VideoFramePayload? {
        guard payload.count >= subHeaderSize else { return nil }
        let base = payload.startIndex
        let pts = payload.readBE(Int64.self, at: base + 0)
        let flags = payload[base + 8]
        let key = (flags & 0x01) == 0x01
        let annex = payload.subdata(in: (base + subHeaderSize)..<payload.endIndex)
        return VideoFramePayload(ptsMicros: pts, isKeyframe: key, annexB: annex)
    }
}

// MARK: - Helpers de leitura/escrita big-endian sobre Data

extension Data {
    /// Acrescenta um inteiro fixo em big-endian.
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var be = value.bigEndian
        // Usa a função global do Swift (Data tem um método instância homônimo).
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    /// Lê um inteiro fixo big-endian em um offset absoluto (índice do Data).
    func readBE<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        let size = MemoryLayout<T>.size
        var value: T = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { dst in
            self.copyBytes(to: dst, from: offset..<(offset + size))
        }
        return T(bigEndian: value)
    }
}
