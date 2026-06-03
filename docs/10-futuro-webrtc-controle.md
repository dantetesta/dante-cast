# 10 · Estratégia de evolução — WebRTC e controle remoto

A arquitetura do MVP foi desenhada para que essas evoluções **não exijam reescrever** captura, encode,
decode ou render. O segredo está em **isolar a camada de transporte** e **adicionar um canal de controle**.

## A. Transporte substituível (TCP → UDP/RTP → WebRTC)

Hoje o transporte é uma implementação concreta atrás de uma interface lógica:

```
Android: FrameSource ──▶ [ Transport ] ──▶ rede
Mac:     rede ──▶ [ Transport ] ──▶ FrameSink
```

`Transport` expõe apenas: `sendVideoConfig`, `sendFrame(pts, keyframe, bytes)`, `onFrame(...)`,
`sendControl(...)`, `onControl(...)`. O DCWP/TCP é a primeira implementação.

### Passo 1 — UDP/RTP (latência menor)
- Trocar o socket TCP por UDP com **empacotamento RTP** (RFC 6184 para H.264) + FEC/retransmissão seletiva.
- Reaproveita 100% do encoder/decoder; muda só o `Transport`.
- Ganho: latência alvo **< 100 ms**; custo: tratar perda/reordenação de pacotes.

### Passo 2 — WebRTC (produção, NAT traversal, adaptativo)
- Substituir o `Transport` por uma `PeerConnection` (Google WebRTC / `libwebrtc`; no Mac, `RTCPeerConnection`
  via framework WebRTC; no Android, `org.webrtc`).
- **Sinalização** reaproveita o pareamento atual: o QR/handshake passa a trocar **SDP offer/answer** e
  **ICE candidates** pelo mesmo canal TCP inicial (ou via um pequeno servidor de sinalização local).
- Vantagens: bitrate adaptativo, jitter buffer, NAT traversal (STUN/TURN → habilita cloud relay), congestionamento.
- O pipeline de mídia (MediaCodec / VideoToolbox) continua igual; o WebRTC pode até usar o codec interno.

> Como o MVP já negocia `settings` no `HELLO_ACK`, a migração para SDP é incremental: a mensagem de
> negociação vira um envelope de SDP.

## B. Canal de controle (entrada Mac → Android)

O controle remoto é **um novo tipo de mensagem** no protocolo (ou um datachannel WebRTC), no sentido
**Mac → Android** — o inverso do vídeo.

### Novos tipos DCWP (reservados para a fase de controle)
```
0x50 INPUT_TOUCH   {action: down|move|up, x, y, pointerId}   (coords normalizadas 0..1)
0x51 INPUT_KEY     {keyCode, action: down|up, meta}
0x52 INPUT_SWIPE   {x1,y1,x2,y2,durationMs}
0x53 NAV_BUTTON    {button: back|home|recents}
```
Coordenadas **normalizadas** (0..1) para serem independentes da resolução real.

### Execução no Android (duas opções)

1. **Accessibility Service** (sem cabo, sem root)
   - `AccessibilityService` + `dispatchGesture(GestureDescription)` para taps/swipes; `performGlobalAction`
     para back/home/recents. Requer o usuário habilitar o serviço em Configurações.
   - Limitações: alguns apps bloqueiam injeção; teclado via `ACTION_SET_TEXT` em campos focados.

2. **ADB bridge** (modo desenvolvedor / suporte técnico)
   - `adb shell input tap/swipe/text` ou `UiAutomator`. Requer depuração USB/Wi‑Fi habilitada.
   - Mais poderoso e confiável, porém exige ADB — ideal para o "modo suporte remoto".

### Mapeamento de entrada no Mac
- Clique do mouse → `INPUT_TOUCH down/up`; arrastar → `move`; scroll → `INPUT_SWIPE`.
- Teclado → `INPUT_KEY`. Botões de navegação na toolbar → `NAV_BUTTON`.
- Mostrar **indicadores de toque/cursor** (overlay) como recurso de apresentação.

## C. Outras evoluções habilitadas pela mesma base

- **Áudio:** novo tipo `AUDIO_CONFIG/AUDIO_FRAME` (AAC/Opus) no mesmo transporte, ou faixa de áudio no WebRTC.
- **Descoberta automática:** NSD/mDNS (`_dantecast._tcp`) — o Mac anuncia, o Android lista, dispensando QR.
- **Multi‑device:** o `MirrorServer` passa a aceitar N conexões, cada uma com sua `Session` e janela/aba.
- **Cloud relay / team sharing:** habilitado naturalmente por WebRTC + TURN.
- **Mini‑controlador na barra de menus:** uma `NSStatusItem` reusando o `AppState`.

## Ordem recomendada de evolução

1. Canal de controle via **Accessibility** (maior valor, sem cabo) sobre o DCWP atual.
2. **Áudio** sobre DCWP.
3. **Descoberta mDNS** (remove fricção do QR).
4. **WebRTC** (latência + NAT + adaptativo) → desbloqueia cloud/relay/team.
5. **USB/ADB** e **multi‑device**.
