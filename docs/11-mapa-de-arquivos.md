# 11 · Mapa de arquivos principais (responsabilidades)

Lista dos arquivos‑chave de cada app e o que cada um faz. (A estrutura real é criada nas pastas
`app_mac/` e `app_android/`; cada uma tem seu próprio README com instruções de build.)

## macOS — `app_mac/Sources/DanteCast/`

| Arquivo | Responsabilidade |
|---------|------------------|
| `App/DanteCastApp.swift` | `@main` SwiftUI App; activation policy `.regular`; injeta o `AppState`. |
| `App/AppState.swift` | Coordenador central: estado de conexão, sessão, settings, latência; liga servidor → decoder → render → gravação. |
| `Models/Device.swift` | Modelo de dispositivo (id, nome, IP, confiável). |
| `Models/Session.swift` | Modelo de sessão (token, resolução, fps, bitrate, status). |
| `Models/Recording.swift` | Metadados de gravação. |
| `Models/StreamSettings.swift` | Presets de qualidade/resolução/fps/bitrate (`Codable`). |
| `Models/ConnectionStatus.swift` | Enum de estado da conexão. |
| `Protocol/WireProtocol.swift` | DCWP v1: cabeçalho, tipos, payloads JSON e binários. Fonte da verdade do framing. |
| `Networking/MirrorServer.swift` | `NWListener` TCP; aceita conexão; valida HELLO; roteia mensagens; PING→PONG. |
| `Networking/MessageReader.swift` | Remonta mensagens DCWP completas a partir do stream TCP. |
| `Decoder/H264Decoder.swift` | VideoToolbox: format desc (SPS/PPS) + `VTDecompressionSession` → `CVPixelBuffer`. |
| `Decoder/AnnexBParser.swift` | Separa NALs Annex‑B e converte para AVCC. |
| `Renderer/VideoRendererView.swift` | `NSViewRepresentable` com `AVSampleBufferDisplayLayer`; aspect‑fit; rotação. |
| `Recording/ScreenRecorder.swift` | `AVAssetWriter` + pixel buffer adaptor; iniciar/parar/append. |
| `Recording/ScreenshotCapture.swift` | Último `CVPixelBuffer` → PNG. |
| `Pairing/QRCodeGenerator.swift` | CoreImage `CIQRCodeGenerator` → QR `NSImage`. |
| `Pairing/PairingService.swift` | Gera token, resolve IP/host, monta payload do QR. |
| `Utilities/NetworkInterfaces.swift` | `getifaddrs` → IPv4 da LAN (prefere en0). |
| `Utilities/Logger.swift` | Wrapper de `os.Logger`. |
| `UI/WelcomeView.swift` | Tela inicial / onboarding. |
| `UI/PairDeviceView.swift` | QR + IP/código manual. |
| `UI/MirrorViewerView.swift` | Viewer + toolbar (Start/Stop/Fullscreen/Always‑on‑top/Screenshot/Record/Quality/Rotate/Disconnect) + latência/status. |
| `UI/SettingsView.swift` | Qualidade, fps, resolução, pasta de gravação, porta. |
| `UI/HelpView.swift` | Troubleshooting. |
| `UI/Components/*` | Componentes reutilizáveis (StatusBadge, LatencyView, etc.). |
| `build_dmg.sh` | Compila com o toolchain Swift, empacota `.app` e gera `DanteCast.dmg`. |
| `Package.swift` / `project.yml` | Abrir no Xcode (SPM) ou gerar `.xcodeproj` (XcodeGen). |

## Android — `app_android/app/src/main/java/com/dantetesta/dantecast/`

| Arquivo | Responsabilidade |
|---------|------------------|
| `DanteCastApp.kt` | `Application`; cria canal de notificação. |
| `MainActivity.kt` | Host do Compose nav; fluxo de permissão de captura (`createScreenCaptureIntent`); permissões runtime. |
| `ui/theme/*` | Tema Material 3 (cores, tipografia, dark mode). |
| `ui/navigation/AppNav.kt` | Navegação entre telas Compose. |
| `ui/WelcomeScreen.kt` | Tela inicial / explicação. |
| `ui/ScanQrScreen.kt` | CameraX + ML Kit; lê o QR; fallback manual. |
| `ui/PermissionScreen.kt` | Explica e dispara a permissão de captura. |
| `ui/StreamingScreen.kt` | Mac conectado, resolução/fps/bitrate, tempo, latência, botão STOP. |
| `ui/SettingsScreen.kt` | Bitrate, fps, resolução (persistidos). |
| `ui/MirrorViewModel.kt` | Estado de pareamento/conexão/stream (`StateFlow`); comandos start/stop. |
| `capture/ScreenCaptureManager.kt` | `VirtualDisplay` da `MediaProjection` no Surface do encoder; orientação; release. |
| `encoder/H264Encoder.kt` | `MediaCodec` H.264 (Surface); emite CODEC_CONFIG e access units; força sync frame. |
| `network/WireProtocol.kt` | DCWP v1 (espelho do lado Swift). |
| `network/MirrorClient.kt` | Socket TCP; HELLO/ACK; envia VIDEO_*; PING/PONG; writer único + fila. |
| `pairing/PairingPayload.kt` | Modelos `@Serializable` (QR, HELLO, HELLO_ACK). |
| `pairing/QrAnalyzer.kt` | `ImageAnalysis.Analyzer` (ML Kit) extraindo o JSON do QR. |
| `service/ScreenMirrorService.kt` | Foreground service `mediaProjection`; orquestra captura+encoder+client; STOP na notificação. |
| `model/StreamSettings.kt`, `model/Quality.kt`, `model/SessionState.kt` | Settings, presets e estados. |
| `res/values/*` | Strings (PT‑BR), tema, cores. |
| `res/mipmap-*`, `res/drawable/*` | Ícone adaptativo e ícone de notificação. |
| `build_apk.sh` | `./gradlew assembleRelease` → copia o APK para `app_android/DanteCast.apk`. |
| `settings.gradle.kts`, `build.gradle.kts`, `app/build.gradle.kts` | Configuração Gradle (Kotlin DSL). |
