import Foundation

/// Tipos de NAL H.264 relevantes para o decode.
enum NALType: UInt8 {
    case nonIDR = 1      // slice de frame não-IDR (P/B)
    case idr = 5         // slice IDR (keyframe)
    case sps = 7         // Sequence Parameter Set
    case pps = 8         // Picture Parameter Set
    case aud = 9         // Access Unit Delimiter
    case sei = 6         // Supplemental Enhancement Information
    case other = 0

    init(headerByte: UInt8) {
        let t = headerByte & 0x1F   // 5 bits inferiores = nal_unit_type
        self = NALType(rawValue: t) ?? .other
    }
}

/// Uma unidade NAL extraída do fluxo Annex-B (sem o start code).
struct NALUnit {
    var type: NALType
    var data: Data      // bytes do NAL, começando pelo header byte
}

/// Conversor Annex-B -> NAL units -> AVCC (length-prefixed).
///
/// Annex-B separa NALs por start codes (00 00 00 01 ou 00 00 01).
/// O VideoToolbox espera o formato AVCC: cada NAL prefixado por seu tamanho
/// em 4 bytes big-endian.
enum AnnexBParser {

    /// Quebra um buffer Annex-B em unidades NAL individuais.
    static func parseNALUnits(_ data: Data) -> [NALUnit] {
        var units: [NALUnit] = []
        let bytes = [UInt8](data)
        let n = bytes.count
        guard n >= 3 else { return units }

        // Encontra os offsets de início de payload (após cada start code)
        // e o tamanho do start code que o precede.
        var starts: [(payloadStart: Int, scLen: Int)] = []
        var i = 0
        while i + 2 < n {
            if bytes[i] == 0x00 && bytes[i + 1] == 0x00 {
                if bytes[i + 2] == 0x01 {
                    // start code de 3 bytes
                    starts.append((i + 3, 3))
                    i += 3
                    continue
                } else if i + 3 < n && bytes[i + 2] == 0x00 && bytes[i + 3] == 0x01 {
                    // start code de 4 bytes
                    starts.append((i + 4, 4))
                    i += 4
                    continue
                }
            }
            i += 1
        }

        // Para cada start, o NAL vai até o início do próximo start code.
        for idx in 0..<starts.count {
            let payloadStart = starts[idx].payloadStart
            // Fim = posição do start code seguinte (payloadStart - scLen), ou fim do buffer.
            let nalEnd: Int
            if idx + 1 < starts.count {
                nalEnd = starts[idx + 1].payloadStart - starts[idx + 1].scLen
            } else {
                nalEnd = n
            }
            guard payloadStart < nalEnd else { continue }
            let nalBytes = Data(bytes[payloadStart..<nalEnd])
            guard let first = nalBytes.first else { continue }
            units.append(NALUnit(type: NALType(headerByte: first), data: nalBytes))
        }

        return units
    }

    /// Converte uma lista de NAL units para o formato AVCC (4-byte length prefix BE).
    /// Ignora AUD/SEI por padrão (não atrapalham, mas mantemos só o essencial).
    static func toAVCC(_ units: [NALUnit], includeParameterSets: Bool = false) -> Data {
        var out = Data()
        for unit in units {
            switch unit.type {
            case .aud:
                continue // delimitadores não vão para o sample
            case .sps, .pps:
                // Parameter sets normalmente vão no format description, não no sample.
                if !includeParameterSets { continue }
            default:
                break
            }
            out.appendBE(UInt32(unit.data.count))
            out.append(unit.data)
        }
        return out
    }

    /// Caminho rápido: converte um access unit Annex-B diretamente para AVCC em UMA
    /// passada e UMA alocação, sem criar `NALUnit`/`Data` intermediários por NAL.
    /// Ignora AUD/SEI. Usado no hot path de decode (por frame, 30-60x/s).
    static func annexBToAVCC(_ data: Data) -> Data {
        // Reserva o tamanho de entrada (saída é ~igual: trocamos start codes 3-4B por len 4B).
        var out = Data(capacity: data.count + 16)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            let n = raw.count
            guard n >= 4 else { return }

            // Localiza o início do primeiro start code.
            var i = 0
            // Função inline: tamanho do start code em `p` (0 = não é start code).
            func scLen(_ p: Int) -> Int {
                if p + 3 < n, base[p] == 0, base[p+1] == 0, base[p+2] == 0, base[p+3] == 1 { return 4 }
                if p + 2 < n, base[p] == 0, base[p+1] == 0, base[p+2] == 1 { return 3 }
                return 0
            }

            // Pula até o primeiro start code.
            while i < n && scLen(i) == 0 { i += 1 }

            while i < n {
                let sc = scLen(i)
                guard sc > 0 else { i += 1; continue }
                let nalStart = i + sc
                guard nalStart < n else { break }
                // Procura o próximo start code (fim deste NAL).
                var j = nalStart
                while j < n && scLen(j) == 0 { j += 1 }
                let nalEnd = (j < n) ? j : n
                let length = nalEnd - nalStart
                if length > 0 {
                    let nalType = base[nalStart] & 0x1F
                    // 9 = AUD, 6 = SEI -> não vão para o sample.
                    if nalType != 9 && nalType != 6 {
                        var be = UInt32(length).bigEndian
                        withUnsafeBytes(of: &be) { out.append(contentsOf: $0) }
                        out.append(base + nalStart, count: length)
                    }
                }
                i = nalEnd
            }
        }
        return out
    }

    /// Extrai (sps, pps) de um buffer Annex-B de configuração.
    static func extractParameterSets(_ data: Data) -> (sps: Data, pps: Data)? {
        let units = parseNALUnits(data)
        let sps = units.first(where: { $0.type == .sps })?.data
        let pps = units.first(where: { $0.type == .pps })?.data
        guard let s = sps, let p = pps else { return nil }
        return (s, p)
    }
}
