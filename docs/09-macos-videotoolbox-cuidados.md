# 09 · Cuidados técnicos com macOS e VideoToolbox

## 1. Formato H.264 bem definido

- O Android emite **Annex‑B** (NALs separados por start codes `00 00 00 01`). O VideoToolbox trabalha com
  **AVCC** (NALs com prefixo de tamanho). É obrigatório **converter Annex‑B → AVCC** antes de montar o
  `CMSampleBuffer` (`nalUnitHeaderLength = 4`).
- SPS/PPS chegam no `VIDEO_CONFIG`; usar `CMVideoFormatDescriptionCreateFromH264ParameterSets`.

## 2. Precisa de keyframe para iniciar

- A `VTDecompressionSession` só produz imagem após um **IDR**. Garantir que o Android force *sync frame*
  ao conectar e a cada rotação. Enquanto não chega IDR, o viewer mostra "aguardando dispositivo".

## 3. Gestão da sessão e do format description

- Ao receber **novo `VIDEO_CONFIG`** (rotação/mudança de resolução), **recriar** o format description e a
  `VTDecompressionSession` (não dá para trocar SPS/PPS de uma sessão ativa).
- Reusar a sessão entre frames do mesmo formato — recriar a cada frame mata a performance.

## 4. Pixel buffers e zero‑copy

- Pedir buffers compatíveis com Metal: `kCVPixelBufferMetalCompatibilityKey = true` e formato
  `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (NV12) para render eficiente.
- `AVSampleBufferDisplayLayer` aceita o `CMSampleBuffer` resultante; manter `controlTimebase` ou usar
  exibição imediata (display‑immediately) para minimizar latência.

## 5. API deprecada no macOS 15

- A partir do macOS 15, vários membros de `AVSampleBufferDisplayLayer` foram movidos para
  `sampleBufferRenderer` (`status`, `flush()`, `enqueue`, `isReadyForMoreMediaData`,
  `flushAndRemoveImage()`). Com **deployment target macOS 13** o código antigo compila (apenas *warnings*).
  Para suportar 15+ de forma limpa, fazer *bridging* condicional via `if #available(macOS 15, *)`.

## 6. Threading

- Alimentar a `VTDecompressionSession` por uma fila serial dedicada; o callback de saída vem em outra
  thread — saltar para `@MainActor` apenas para atualizar a UI/estado, nunca para mover pixels.

## 7. Gravação e screenshot a partir do CVPixelBuffer

- **Gravação:** `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor`; apendar `CVPixelBuffer` com PTS.
  Iniciar a sessão de escrita com `startSession(atSourceTime:)` no primeiro frame.
- **Screenshot:** `CIImage(cvPixelBuffer:)` → `CIContext` → `CGImage` → PNG. Operar sobre uma cópia do
  último buffer para não competir com o render.

## 8. Rede com Network.framework

- `NWListener` sobre TCP; aceitar uma conexão por vez no MVP.
- Ler em modo *streaming* (`receive(minimumIncompleteLength:maximumLength:)`) e remontar via `MessageReader`.
- Tratar `.failed`/`.cancelled` para refletir desconexão na UI.

## 9. Empacotamento / distribuição

- Build via toolchain Swift de linha de comando → bundle `.app` → `.dmg` (script `build_dmg.sh`).
- **Sem Xcode:** funciona para gerar o app, mas para distribuição em escala é recomendável **assinar
  (Developer ID) + notarizar**. App não assinado: primeiro launch via botão direito → **Abrir**.
- **App Sandbox + Local Network:** se for distribuir via App Store, será necessário entitlement de rede
  local e descrição de uso. Para distribuição direta (.dmg), ad‑hoc sign já permite rodar.

## Checklist de release macOS

- [ ] Annex‑B → AVCC correto (`nalUnitHeaderLength = 4`)
- [ ] Recriar sessão ao mudar formato
- [ ] Aguarda keyframe antes de exibir
- [ ] Pixel format Metal‑compatível
- [ ] Render/gravação/screenshot a partir do mesmo `CVPixelBuffer`
- [ ] (Distribuição) assinar + notarizar
