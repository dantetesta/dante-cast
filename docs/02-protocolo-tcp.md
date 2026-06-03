# 02 · Protocolo de comunicação — DCWP v1

**DCWP** = *Dante Cast Wire Protocol*. É o contrato **único** entre Mac e Android.
Implementado em `app_mac/.../Protocol/WireProtocol.swift` e `app_android/.../network/WireProtocol.kt`.
Qualquer alteração incompatível **incrementa o byte `version`**.

## Fundamentos

- **Transporte:** TCP. O **Mac** é o **servidor** (escuta). O **Android** é o **cliente** (conecta).
- **Endianness:** todos os inteiros multi‑byte são **big‑endian** (network byte order).
- **Enquadramento (framing):** toda mensagem = **cabeçalho fixo de 12 bytes** + payload de tamanho variável.
  Como TCP é um stream, o receptor precisa de um *MessageReader* que acumula bytes até ter cabeçalho + payload completos.

## Cabeçalho (12 bytes)

| Offset | Tamanho | Campo          | Valor / descrição                                  |
|-------:|--------:|----------------|----------------------------------------------------|
| 0      | 4       | `magic`        | ASCII `"DCWP"` = `0x44 0x43 0x57 0x50`             |
| 4      | 1       | `version`      | `0x01`                                              |
| 5      | 1       | `type`         | tipo da mensagem (tabela abaixo)                    |
| 6      | 2       | `flags`        | uint16 reservado (= `0`)                            |
| 8      | 4       | `payloadLength`| uint32 big‑endian; **rejeitar se > 16 MiB**         |

Leitura: confere `magic` + `version`; se não bater, fecha a conexão (stream dessincronizado).

## Tipos de mensagem (`type`)

| Hex    | Nome           | Direção   | Payload                |
|--------|----------------|-----------|------------------------|
| `0x01` | `HELLO`        | A → M     | JSON                   |
| `0x02` | `HELLO_ACK`    | M → A     | JSON                   |
| `0x10` | `VIDEO_CONFIG` | A → M     | binário (SPS/PPS)      |
| `0x11` | `VIDEO_FRAME`  | A → M     | binário (access unit)  |
| `0x20` | `ORIENTATION`  | A → M     | JSON                   |
| `0x30` | `PING`         | ambos     | binário 8 bytes        |
| `0x31` | `PONG`         | ambos     | binário 8 bytes        |
| `0x40` | `STREAM_STOP`  | ambos     | vazio                  |
| `0x41` | `BYE`          | ambos     | vazio                  |
| `0x42` | `ERROR`        | ambos     | JSON                   |

## Payloads JSON (UTF‑8)

**HELLO** (Android → Mac):
```json
{
  "protocolVersion": 1,
  "token": "<token vindo do QR>",
  "device": { "id": "<uuid>", "name": "Pixel 7", "model": "Pixel 7", "osVersion": "34" },
  "capabilities": { "maxWidth": 1080, "maxHeight": 2400, "fpsOptions": [30, 60] }
}
```

**HELLO_ACK** (Mac → Android):
```json
{
  "accepted": true,
  "reason": "",
  "macName": "MacBook do Dante",
  "sessionId": "<uuid>",
  "settings": { "width": 1080, "height": 1920, "fps": 30, "bitrate": 8000000, "codec": "h264" }
}
```
Se `accepted=false`, `reason` explica (`"bad token"`, `"version mismatch"`) e o Mac fecha a conexão.

**ORIENTATION** (Android → Mac): `{ "width": 1920, "height": 1080, "rotation": 90 }`
Em rotação, o Android também **re‑envia `VIDEO_CONFIG`** (novos SPS/PPS, pois a dimensão muda) e **força um keyframe**.

**ERROR**: `{ "code": "ENCODER_FAIL", "message": "..." }`

## Payloads binários

**VIDEO_CONFIG** — configuração do codec (uma vez no início e a cada mudança de dimensão):
```
[ width  : uint16 ]
[ height : uint16 ]
[ fps    : uint16 ]
[ flags  : uint16 ]   (reservado = 0)
[ SPS + PPS em Annex-B ... ]   (bytes do buffer CODEC_CONFIG do MediaCodec, com start codes 00 00 00 01)
```

**VIDEO_FRAME** — uma unidade de acesso H.264 por mensagem:
```
[ ptsMicros : int64  ]   (timestamp de apresentação em microssegundos)
[ flags     : uint8  ]   (bit0 = 1 → keyframe/IDR)
[ reserved  : 3 bytes]
[ access unit em Annex-B ... ]
```

**PING / PONG** — 8 bytes:
```
[ nanos : int64 ]   (relógio monotônico do remetente; o PONG ecoa o mesmo valor)
```
RTT/latência = `(now − nanos_ecoado) / 2`. Enviado a cada ~2 s.

## QR Code de pareamento

O Mac codifica este JSON no QR (e mostra `ip`/`porta`/`token` para entrada manual):
```json
{ "v": 1, "ip": "192.168.0.42", "port": 7843, "token": "<token-aleatório>", "name": "MacBook do Dante" }
```
Porta TCP padrão: **7843**.

## Máquina de estados da sessão

```
        ┌─────────┐   bind+QR    ┌───────────┐  TCP accept  ┌────────────┐
        │  idle   │ ───────────▶ │ listening │ ───────────▶ │ connecting │
        └─────────┘              └───────────┘              └─────┬──────┘
                                                                  │ HELLO/HELLO_ACK ok
                                          STREAM_STOP             ▼
        ┌──────────────┐   BYE / erro   ┌───────────┐  VIDEO_*  ┌───────────┐
        │ disconnected │ ◀───────────── │ streaming │ ◀──────── │  paired   │
        └──────────────┘                └───────────┘           └───────────┘
```

## Notas de implementação

- **Annex‑B → AVCC (Mac):** cada NAL `00 00 00 01 <nal>` é convertido para `<len uint32 BE><nal>` antes de
  montar o `CMSampleBuffer`. `nalUnitHeaderLength = 4`.
- **Keyframe inicial:** o decoder VideoToolbox precisa de um IDR para começar; o Android força *sync frame*
  ao conectar (`PARAMETER_KEY_REQUEST_SYNC_FRAME`).
- **Backpressure:** o `MirrorClient` usa um *writer* único com fila limitada. Se a rede não vazão,
  descarta frames inter (P‑frames) antes de descartar keyframes (estratégia simples de degradação).
- **Segurança:** o token é de uso único por sessão; conexões sem token válido são recusadas.
  Transporte criptografado (TLS/DTLS) fica para versões futuras (ver doc 10).
