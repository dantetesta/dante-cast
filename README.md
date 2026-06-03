# Dante Cast 📱→💻

Sistema de **espelhamento de tela Android no Mac** pela rede local, com baixa latência,
interface bonita e pareamento simples por QR Code. Engine própria (H.264 + TCP), **sem dependência de scrcpy**.

> Projeto interno: _DroidMirror Studio_ · Nome comercial do app: **Dante Cast**

## ⬇️ Downloads (para clientes)

Builds prontos na página de **[Releases](https://github.com/dantetesta/dante-cast/releases/latest)**:

| Plataforma | Arquivo | Observação |
|-----------|---------|------------|
| 🍎 macOS (Apple Silicon, 13+) | **DanteCast.dmg** | Não assinado: no 1º uso, botão direito → **Abrir**. |
| 🤖 Android (8.0+ / API 26+) | **DanteCast.apk** | Instale via sideload (ative "Fontes desconhecidas"). |
| 🤖 Android (fallback) | **DanteCast-debug.apk** | Variante debug, sempre instalável. |

Repositório: **https://github.com/dantetesta/dante-cast** · CI: GitHub Actions (compila e publica os binários a cada tag `v*`).

### 🆕 Novidades v1.1.0 (polimento Apple-grade)

**Performance / anti-lag**
- 🍎 Decodificação movida para **fora da main thread** (eliminado o gargalo de UI por frame).
- 🍎 Buffer do decoder com **1 cópia por frame** (antes 3-4) + `AnnexBParser` em passada única.
- 🍎 `VTDecompressionSession` em **modo tempo-real**; `CMVideoFormatDescription` cacheado no render.
- 🍎 `MessageReader` com cursor (sem `removeSubrange` O(n) por mensagem).
- 🤖 Fila de transmissão reduzida **64 → 6** frames (corta o acúmulo de latência sob congestão).
- 🤖 Encoder com **baixa latência**: `KEY_LOW_LATENCY`, `KEY_PRIORITY=0`, `KEY_OPERATING_RATE`, `KEY_LATENCY=1`.

**UI / features**
- 🖼️ **Moldura de smartphone** no espelhamento (skin de celular com dynamic island) — ativável.
- 🌓 Seletor de **aparência** (Sistema / Claro / Escuro).
- 🎙️ **Gravação com ou sem áudio** do microfone (A/V sincronizados no host clock).
- 🎛️ **Toolbar redesenhada**: botões grandes, com rótulo, agrupados e com feedback de hover/ativo.

```
┌──────────────────────┐        Wi‑Fi / LAN         ┌──────────────────────┐
│   Android (Companion) │  ──── H.264 sobre TCP ───▶ │     Mac (Receiver)    │
│  MediaProjection →    │      protocolo DCWP v1     │  Network.framework →  │
│  MediaCodec (encode)  │                            │  VideoToolbox (decode)│
│  TCP client           │                            │  AVSampleBufferLayer  │
└──────────────────────┘                            └──────────────────────┘
        captura + envia                                   recebe + exibe + grava
```

## Estrutura do repositório

```
Espelhamento/
├── README.md              ← este arquivo
├── docs/                  ← arquitetura, protocolo e fluxos (deliverables 1–14)
│   ├── 01-arquitetura.md
│   ├── 02-protocolo-tcp.md          (DCWP v1 — contrato único Mac↔Android)
│   ├── 03-pareamento.md
│   ├── 04-captura-android.md
│   ├── 05-decodificacao-mac.md
│   ├── 06-modelos-de-dados.md
│   ├── 07-roadmap.md
│   ├── 08-android14-cuidados.md
│   ├── 09-macos-videotoolbox-cuidados.md
│   ├── 10-futuro-webrtc-controle.md
│   └── 11-mapa-de-arquivos.md
├── app_mac/               ← app macOS (Swift/SwiftUI). Build: DanteCast.dmg na raiz.
└── app_android/           ← app Android (Kotlin/Compose). Build: DanteCast.apk na raiz.
```

## Como o sistema funciona (resumo de 1 minuto)

1. O **Mac** abre um servidor TCP, gera um *session token* e mostra um **QR Code** com `ip`, `porta` e `token`.
2. O **Android** escaneia o QR, conecta no Mac e envia um `HELLO` com o token.
3. O Mac valida o token e responde `HELLO_ACK` com as configurações negociadas.
4. O Android pede permissão de **captura de tela** (`MediaProjection`); ao conceder, inicia um
   *foreground service* que captura a tela, codifica em **H.264** (`MediaCodec`) e envia os frames.
5. O Mac recebe os pacotes, remonta os frames, **decodifica com VideoToolbox** e exibe em tempo real.
6. Latência medida via `PING/PONG`. Ambos os lados podem encerrar com `BYE`.

Detalhes byte‑a‑byte do protocolo em [`docs/02-protocolo-tcp.md`](docs/02-protocolo-tcp.md).

## Builds (entregáveis para clientes)

| Plataforma | Artefato                   | Como gerar                                            |
|-----------|-----------------------------|-------------------------------------------------------|
| macOS     | `app_mac/DanteCast.dmg`     | `cd app_mac && ./build_dmg.sh` (Swift toolchain)      |
| Android   | `app_android/DanteCast.apk` | `cd app_android && ./build_apk.sh` (Android Studio/SDK)|

> **macOS:** o `.dmg` é gerado direto pelo toolchain Swift de linha de comando (não exige Xcode completo).
> O app é distribuído **sem assinatura Developer ID** por enquanto — no primeiro uso o cliente deve
> clicar com o botão direito → **Abrir**. Para distribuição em escala, assinar + notarizar com conta Apple Developer.
>
> **Android:** o `.apk` exige Android Studio (ou Android SDK + Gradle) instalado para compilar.
> O script `build_apk.sh` roda `./gradlew assembleRelease` e copia o APK para a raiz da pasta.

## Escopo do MVP

✅ Espelhamento Android→Mac · qualidade Baixa/Média/Alta · 720p/1080p · 30fps · QR + IP manual
· iniciar/parar no Android · desconectar/screenshot/gravação/fullscreen/always‑on‑top no Mac · tratamento de erro.

🚫 Fora do MVP: controle remoto, áudio, WebRTC, cloud relay, multi‑device, login/assinatura.
(Estratégia de evolução em [`docs/10-futuro-webrtc-controle.md`](docs/10-futuro-webrtc-controle.md).)

## Metas de performance (MVP)

- Latência: **< 250 ms** em Wi‑Fi boa
- Resolução: 720p e 1080p · FPS: 30 estável · Bitrate: 2–12 Mbps configurável
- Mac: Apple Silicon primeiro
