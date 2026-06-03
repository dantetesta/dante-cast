# 01 · Arquitetura técnica detalhada

## Visão geral

Dante Cast é composto por **dois aplicativos** que se comunicam por uma conexão **TCP** na rede local:

- **Android (Companion)** — captura a tela, codifica em H.264 e **envia** (papel de *cliente* TCP / *sender*).
- **macOS (Receiver)** — **recebe**, decodifica, exibe, grava e captura screenshots (papel de *servidor* TCP / *viewer*).

A separação de papéis é deliberada: o Mac é quem o usuário "controla" e onde o conteúdo é consumido,
então ele hospeda o servidor e gera o QR de pareamento. O celular é descartável/efêmero e apenas conecta.

```
ANDROID (sender)                                   MAC (receiver)
─────────────────                                  ──────────────
MediaProjection                                    NWListener (Network.framework)
   │ Surface                                           │  bytes TCP
   ▼                                                    ▼
MediaCodec (H.264, COLOR_FormatSurface)            MessageReader (remonta frames DCWP)
   │ access units (Annex-B)                            │ VIDEO_CONFIG / VIDEO_FRAME
   ▼                                                    ▼
Packetizer (DCWP v1)                               AnnexBParser → AVCC
   │                                                    ▼
MirrorClient (TCP socket) ───────── TCP ─────────▶ H264Decoder (VTDecompressionSession)
                                                        │ CVPixelBuffer
                                                        ├─▶ AVSampleBufferDisplayLayer (tela)
                                                        ├─▶ ScreenRecorder (AVAssetWriter)
                                                        └─▶ ScreenshotCapture (PNG)
```

## Princípios de design

1. **Camada de transporte substituível.** O `WireProtocol`/`MirrorClient` (Android) e
   `WireProtocol`/`MirrorServer` (Mac) isolam o framing. Trocar TCP por UDP/RTP ou WebRTC no futuro
   não toca na captura/encode nem na decodificação/render. Veja [10-futuro-webrtc-controle.md](10-futuro-webrtc-controle.md).
2. **Pipeline em estágios desacoplados.** Cada estágio (captura → encode → rede → decode → render)
   tem entrada/saída bem definidas e roda em sua própria fila/coroutine, evitando que o socket
   bloqueie o encoder ou o render.
3. **Contrato único (DCWP v1).** Mac e Android implementam o mesmo cabeçalho de 12 bytes e os mesmos
   tipos de mensagem. É a fonte da verdade — qualquer mudança é versionada pelo byte `version`.
4. **Apple Silicon primeiro / Android moderno.** VideoToolbox com decode acelerado por hardware;
   `MediaCodec` em modo Surface (zero‑copy GPU). Compatível com Android 14+ (foreground service tipado).
5. **UI bonita e simples.** SwiftUI + AppKit bridge onde necessário; Jetpack Compose Material 3.

## Pipeline Android (sender)

1. `MediaProjectionManager.createScreenCaptureIntent()` → usuário concede permissão.
2. Inicia **foreground service** com `foregroundServiceType=mediaProjection` (obrigatório no Android 14+).
3. Cria `VirtualDisplay` a partir da `MediaProjection`, ligando a saída ao **Surface** de entrada do `MediaCodec`.
4. `MediaCodec` codifica em **H.264** (`COLOR_FormatSurface`, bitrate/fps/I‑frame configuráveis).
5. Buffers de saída: o buffer com `BUFFER_FLAG_CODEC_CONFIG` vira `VIDEO_CONFIG` (SPS/PPS);
   os demais viram `VIDEO_FRAME` (com flag de keyframe quando `BUFFER_FLAG_KEY_FRAME`).
6. `Packetizer` envolve cada unidade no framing DCWP e enfileira no `MirrorClient`.
7. `MirrorClient` (writer único + fila) envia pela TCP. Mudanças de orientação re‑enviam `VIDEO_CONFIG` + keyframe.

## Pipeline Mac (receiver)

1. `MirrorServer` (NWListener) aceita uma conexão e lê o stream de bytes.
2. `MessageReader` remonta mensagens DCWP completas (length‑prefixed).
3. `HELLO` é validado (token + versão) → responde `HELLO_ACK`.
4. `VIDEO_CONFIG`: `AnnexBParser` extrai SPS/PPS → `H264Decoder` cria o `CMVideoFormatDescription`.
5. `VIDEO_FRAME`: Annex‑B → AVCC (length‑prefix 4 bytes) → `CMSampleBuffer` → `VTDecompressionSession`.
6. Saída `CVPixelBuffer` → render em `AVSampleBufferDisplayLayer`; cópia para screenshot; append no `AVAssetWriter` se gravando.
7. `PING/PONG` mede latência; `BYE`/`STREAM_STOP` encerram com elegância.

## Threading / concorrência

| Estágio            | Android                                   | Mac                                            |
|--------------------|-------------------------------------------|------------------------------------------------|
| Captura            | thread do `VirtualDisplay` (sistema)      | —                                              |
| Encode/Decode      | callback do `MediaCodec` (coroutine IO)   | fila do `VTDecompressionSession`               |
| Rede               | 1 coroutine *writer* + fila *outbound*    | fila do `NWConnection` (Network.framework)     |
| UI                 | Main/Compose (observa `StateFlow`)        | `@MainActor` (observa `@Published`/AppState)   |

A regra de ouro: **a rede nunca bloqueia o encoder/decoder**, e a **UI nunca toca em buffers de vídeo** —
apenas observa estado (status, latência, dimensões).

## Tratamento de erros / resiliência

- Token inválido ou versão incompatível → `HELLO_ACK{accepted:false}` + fechamento limpo.
- Queda de Wi‑Fi → detecção de socket fechado, estado `disconnected`, UI oferece reconectar.
- Sem keyframe no início → Mac aguarda IDR; Android força *sync frame* ao conectar e a cada rotação.
- Frame maior que 16 MiB → rejeitado (proteção contra payload corrompido).
