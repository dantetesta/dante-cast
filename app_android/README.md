# Dante Cast — App Android (cliente)

Aplicativo companheiro que **captura a tela do Android** e transmite **H.264 sobre TCP**
para o receptor macOS ("Dante Cast" no Mac). O Mac é o **servidor** (escuta); o Android é o
**cliente** (conecta no `ip:port` do Mac, lido via QR Code).

- Kotlin + Jetpack Compose (Material 3)
- `minSdk 26`, `compileSdk 35`, `targetSdk 35`
- `applicationId`: `com.dantetesta.dantecast`
- Rótulo do app: **Dante Cast**

---

## Como construir o APK

> ⚠️ **Esta máquina NÃO possui Gradle nem o Android SDK instalados.** O projeto foi
> escrito para compilar em uma máquina com o ambiente Android completo. Não tente
> baixar o SDK aqui.

### Requisitos
- **Android Studio** (recomendado) **ou** o **Android SDK** via linha de comando
- **compileSdk 34 ou 35** instalado no SDK Manager
- **JDK 17+** (o Java 21 desta máquina serve)
- **`gradle-wrapper.jar`**: NÃO incluído (binário). É regenerado automaticamente quando
  você abre o projeto no Android Studio, ou manualmente com:
  ```bash
  gradle wrapper --gradle-version 8.9
  ```

### Opção A — Android Studio (mais simples)
1. Abra a pasta `app_android/` no Android Studio (Giraffe/Koala ou mais novo).
2. Aceite o download de SDK/plugins quando solicitado (Android Studio cria o
   `gradle-wrapper.jar` e sincroniza).
3. Menu **Build → Build Bundle(s)/APK(s) → Build APK(s)**.
4. O APK de debug sai em `app/build/outputs/apk/debug/app-debug.apk`.
   Para release: **Build → Generate Signed Bundle / APK** (ou use o script abaixo).

### Opção B — Linha de comando
Com o SDK configurado (`ANDROID_HOME`/`ANDROID_SDK_ROOT` apontando para o SDK e um
`local.properties` com `sdk.dir=...`, que o Android Studio cria automaticamente):

```bash
cd app_android
./build_apk.sh            # gera o release e copia para app_android/DanteCast.apk
# ou
./build_apk.sh debug      # gera o debug e copia para app_android/DanteCast.apk
```

O `build_apk.sh` roda `./gradlew :app:assembleRelease` (ou `assembleDebug`) e copia o
APK resultante para **`app_android/DanteCast.apk`**.

> Sobre assinatura: por simplicidade, o `release` está configurado para usar a chave de
> **debug** (`signingConfig = signingConfigs.getByName("debug")`), permitindo
> `assembleRelease` sem keystore. Para distribuição real, configure um `signingConfig`
> próprio em `app/build.gradle.kts`.

---

## Estrutura do projeto

```
app_android/
├── build.gradle.kts                 # plugins (apply false): AGP, Kotlin, Compose, Serialization
├── settings.gradle.kts              # pluginManagement + dependencyResolutionManagement
├── gradle.properties                # AndroidX, jvm args, caching
├── gradle/
│   ├── libs.versions.toml           # Version Catalog (fonte única das versões)
│   └── wrapper/gradle-wrapper.properties  # Gradle 8.9 (jar regenerado pelo Studio)
├── gradlew, gradlew.bat             # wrapper scripts
├── build_apk.sh                     # build + copia DanteCast.apk
└── app/
    ├── build.gradle.kts             # Compose, deps (Compose BOM, CameraX, ML Kit, etc.)
    ├── proguard-rules.pro
    └── src/main/
        ├── AndroidManifest.xml      # permissões + foregroundServiceType="mediaProjection"
        ├── java/com/dantetesta/dantecast/
        │   ├── DanteCastApp.kt          # Application + canal de notificação
        │   ├── MainActivity.kt          # nav Compose + fluxo MediaProjection + permissões
        │   ├── model/                   # Quality, StreamSettings, SessionState, SettingsRepository
        │   ├── pairing/                 # PairingPayload (@Serializable), QrAnalyzer (ML Kit)
        │   ├── network/                 # WireProtocol (DCWP v1), MirrorClient (TCP)
        │   ├── encoder/                 # H264Encoder (MediaCodec, Surface)
        │   ├── capture/                 # ScreenCaptureManager (MediaProjection → VirtualDisplay)
        │   ├── service/                 # ScreenMirrorService (foreground), SessionBus
        │   └── ui/                      # Compose: Welcome/ScanQr/Permission/Streaming/Settings
        │       ├── navigation/AppNav.kt
        │       └── theme/               # Color, Theme, Type (Material 3, dark-aware)
        └── res/                         # strings (PT-BR), themes, ícone adaptativo (vetor), etc.
```

---

## Requisitos do Android 14+ (API 34/35) — tratados aqui

Estes pontos são **obrigatórios** nas versões recentes do Android e estão implementados:

1. **Permissões de foreground service**: o manifesto declara
   `FOREGROUND_SERVICE` e `FOREGROUND_SERVICE_MEDIA_PROJECTION`, e o serviço usa
   `android:foregroundServiceType="mediaProjection"`.
2. **Ordem do `startForeground`**: o `ScreenMirrorService` chama
   `startForeground(..., FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)` **ANTES** de obter a
   `MediaProjection` e de criar o `VirtualDisplay`. A Activity primeiro obtém o token
   (`MediaProjectionManager.createScreenCaptureIntent`), inicia o serviço e só então o
   serviço cria a projeção.
3. **`MediaProjection.Callback`**: registrado em `ScreenCaptureManager` **antes** de criar
   o `VirtualDisplay`; quando `onStop()` dispara (projeção revogada pelo sistema/usuário),
   a captura é encerrada de forma limpa.
4. **`POST_NOTIFICATIONS` (API 33+)**: solicitado em runtime pela `MainActivity` para que a
   notificação do serviço apareça.
5. **Token de uso único**: a permissão de captura é **re-solicitada a cada sessão** (não é
   guardada), conforme exigido.

A câmera (`CAMERA`) é usada **apenas** para ler o QR Code de pareamento.

---

## Fluxo de uso (handshake)

1. Abra o **Dante Cast no Mac** → ele exibe um QR Code.
2. No Android: **Conectar ao Mac** → **escanear o QR** (ou inserir IP/porta/token manualmente).
3. **Autorizar a captura de tela** (diálogo do sistema).
4. O app conecta via TCP em `ip:port`, envia **HELLO(token)** e aguarda **HELLO_ACK**.
5. Se aceito: inicia o **foreground service** + **captura** + **encoder**, envia
   **VIDEO_CONFIG** e os **VIDEO_FRAME**, com **PING/PONG ~2s** para latência.
6. **PARAR** envia **BYE** e encerra tudo.

---

## DCWP v1 — Wire Protocol (deve casar byte-a-byte com o lado macOS)

- Transporte **TCP**, inteiros **BIG-ENDIAN**.
- Cabeçalho de **12 bytes**: magic `"DCWP"` (4) + version `0x01` (1) + type (1) +
  flags uint16 (2) + payloadLength uint32 (4). Payload máximo: **16 MiB**.
- Tipos: `0x01 HELLO`, `0x02 HELLO_ACK`, `0x10 VIDEO_CONFIG`, `0x11 VIDEO_FRAME`,
  `0x20 ORIENTATION`, `0x30 PING`, `0x31 PONG`, `0x40 STREAM_STOP`, `0x41 BYE`,
  `0x42 ERROR`.
- **VIDEO_CONFIG**: `[width u16][height u16][fps u16][flags u16]` + SPS/PPS em **Annex-B**
  (exatamente o buffer `BUFFER_FLAG_CODEC_CONFIG` do MediaCodec).
- **VIDEO_FRAME**: `[ptsMicros i64][flags u8 (bit0=keyframe)][reserved 3B]` + um access unit
  H.264 em **Annex-B**.
- **PING/PONG**: `int64` (System.nanoTime) ecoado de volta.

Implementação canônica: `network/WireProtocol.kt` (fonte única do framing).

---

## Notas

- O `gradle-wrapper.jar` foi intencionalmente omitido (é um binário e não pôde ser baixado
  neste ambiente). Ele é recriado pelo Android Studio na primeira sincronização ou via
  `gradle wrapper --gradle-version 8.9`.
- Sem o Android SDK instalado, **não é possível compilar nesta máquina** — o build deve ser
  feito no Android Studio / em uma máquina com o SDK.
- Comentários do código estão em PT-BR nas partes de lógica relevante.
