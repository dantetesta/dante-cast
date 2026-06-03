# Dante Cast — macOS (receptor)

Receptor de espelhamento de tela Android para macOS. O Mac atua como **servidor**:
escuta numa porta TCP, exibe um QR de pareamento e recebe vídeo H.264 do app
Android (cliente), decodifica via VideoToolbox e exibe em tempo real.

- **Plataforma:** macOS 13+ (Apple Silicon / arm64)
- **Protocolo:** DCWP v1 (ver `Sources/DanteCast/Protocol/WireProtocol.swift`)
- **Codec:** H.264 (Annex-B → AVCC → VideoToolbox)
- **Porta padrão:** 7843

---

## Como construir (sem Xcode)

O projeto compila com o **toolchain de linha de comando do Swift** (não requer
Xcode). O script `build_dmg.sh` faz tudo: compila, monta o `.app`, gera o ícone,
assina (ad-hoc) e cria o `DanteCast.dmg`.

```bash
cd app_mac
./build_dmg.sh
```

Saída: `app_mac/DanteCast.dmg` (read-only, contendo `DanteCast.app` + atalho para
`/Applications`).

### O que o script faz
1. Compila todas as fontes em `Sources/DanteCast/` com
   `xcrun --sdk macosx swiftc -O -target arm64-apple-macosx13.0 …`.
2. Monta `DanteCast.app/Contents/{MacOS,Info.plist,Resources}` com um Info.plist
   completo (CFBundleName "Dante Cast", id `com.dantetesta.dantecast.mac`,
   `LSMinimumSystemVersion 13.0`, `NSHighResolutionCapable`, `NSPrincipalClass`).
3. Gera um ícone `.icns` programaticamente (best-effort — se falhar, o build
   continua sem ícone).
4. Assina em modo **ad-hoc** (`codesign -s - --force --deep`).
5. Cria o `.dmg` via `hdiutil`.

> O build acontece num diretório temporário fora do Desktop para evitar que
> atributos estendidos (iCloud/fileprovider) quebrem o `codesign --strict`.

---

## Como rodar

### A partir do DMG
1. Abra `DanteCast.dmg` e arraste `Dante Cast` para `Applications` (ou rode direto).
2. **App não assinado:** no primeiro launch o macOS bloqueia. Faça
   **clique-direito → Abrir** (ou Ajustes do Sistema → Privacidade e Segurança →
   "Abrir mesmo assim"). Depois disso abre normalmente.
3. Na primeira conexão o macOS pode pedir permissão de **rede local** — permita.

### Uso
1. Clique em **Iniciar e Parear** → um QR code aparece.
2. No app Android Dante Cast, escaneie o QR (ou digite IP + porta + código).
3. A tela do Android aparece no visualizador. Use a toolbar para:
   tela cheia, manter no topo, girar, captura de tela, gravar (.mov), qualidade,
   desconectar. Latência e status são mostrados em tempo real.

Mac e Android devem estar **na mesma rede Wi-Fi/LAN**.

---

## Desenvolvimento

Compilação rápida só para checar erros (sem empacotar):

```bash
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun --sdk macosx swiftc -O -target arm64-apple-macosx13.0 -sdk "$SDK" \
  $(find Sources/DanteCast -name '*.swift') -o /tmp/DanteCast
```

### Estrutura

```
Sources/DanteCast/
  App/            DanteCastApp (@main), AppState (coordenador central)
  Models/         Device, Session, Recording, StreamSettings, ConnectionStatus
  Protocol/       WireProtocol (DCWP v1 — framing, payloads, sub-headers)
  Networking/     MirrorServer (NWListener TCP), MessageReader (parser incremental)
  Decoder/        H264Decoder (VideoToolbox), AnnexBParser (Annex-B↔AVCC)
  Renderer/       VideoRendererView (AVSampleBufferDisplayLayer)
  Recording/      ScreenRecorder (AVAssetWriter), ScreenshotCapture (PNG)
  Pairing/        QRCodeGenerator (CoreImage), PairingService
  Utilities/      NetworkInterfaces (getifaddrs), Logger (os.Logger)
  UI/             Welcome, PairDevice, MirrorViewer, Settings, Help, ContentView
                  + Components/ (StatusBadge, LatencyView, ToolbarButton)
```

### Abrir no Xcode (opcional)

Há um `project.yml` para [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open DanteCast.xcodeproj
```

---

## Protocolo DCWP v1 (resumo)

TCP, Mac = servidor. Todos os inteiros multi-byte são **big-endian**.
Header de 12 bytes: `"DCWP"` + version(1) + type + flags(u16) + payloadLength(u32).

| Tipo | Código | Direção | Payload |
|------|--------|---------|---------|
| HELLO | 0x01 | A→M | JSON (token, device, capabilities) |
| HELLO_ACK | 0x02 | M→A | JSON (accepted, macName, sessionId, settings) |
| VIDEO_CONFIG | 0x10 | A→M | [w,h,fps,flags u16] + SPS/PPS Annex-B |
| VIDEO_FRAME | 0x11 | A→M | [pts i64][flags u8][rsv 3] + access unit Annex-B |
| ORIENTATION | 0x20 | A→M | JSON (width,height,rotation) |
| PING / PONG | 0x30 / 0x31 | ↔ | int64 nanos (eco) |
| STREAM_STOP / BYE | 0x40 / 0x41 | A→M | vazio |
| ERROR | 0x42 | ↔ | JSON (code, message) |

QR de pareamento: `{"v":1,"ip":"…","port":7843,"token":"…","name":"…"}`.

Detalhes byte-a-byte: `Sources/DanteCast/Protocol/WireProtocol.swift`.

---

## Limitações conhecidas

- **App não assinado / não notarizado** → exige clique-direito → Abrir no primeiro
  uso. Distribuição ampla exigiria Developer ID + notarização (precisa de conta
  paga e do Xcode/altool).
- **Sem Xcode neste ambiente:** o build é 100% via `swiftc`. Não há `.xcodeproj`
  versionado (use `project.yml` + XcodeGen se quiser).
- **Decode H.264 apenas** (sem HEVC). É necessário um **keyframe (IDR)** para
  iniciar a exibição; frames anteriores ao primeiro IDR são descartados.
- A latência exibida é uma **estimativa** (RTT do PING/PONG ÷ 2), não inclui o
  pipeline de captura/encode do Android.
- Aceita **uma conexão por vez**; conexões adicionais são recusadas.
- Pixel format de saída fixado em **BGRA**; gravação em H.264 via AVAssetWriter.
