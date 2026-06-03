# 05 · Fluxo de decodificação no Mac

Caminho completo: **TCP → MessageReader → AnnexBParser → VideoToolbox → CVPixelBuffer → render/gravação**.

## Passo a passo

```
1. MirrorServer (NWListener) aceita a conexão e recebe bytes TCP.
       ▼
2. MessageReader acumula bytes e emite mensagens DCWP completas.
       ▼
3. VIDEO_CONFIG:
       │  AnnexBParser separa SPS e PPS dos start codes
       │  CMVideoFormatDescriptionCreateFromH264ParameterSets(
       │       parameterSetCount: 2, [SPS, PPS], nalUnitHeaderLength: 4)
       │  → cria/recria a VTDecompressionSession
       ▼
4. VIDEO_FRAME:
       │  AnnexBParser divide os NALs do access unit
       │  cada NAL Annex-B  (00 00 00 01 <nal>)  →  AVCC  (<len uint32 BE> <nal>)
       │  monta CMBlockBuffer → CMSampleBuffer (com PTS = ptsMicros)
       │  VTDecompressionSessionDecodeFrame(...)
       ▼
5. Callback do VideoToolbox → CVPixelBuffer (NV12/BGRA, GPU‑backed)
       ├──▶ VideoRendererView: envolve em CMSampleBuffer e enqueue na AVSampleBufferDisplayLayer
       ├──▶ ScreenshotCapture: guarda o último CVPixelBuffer (PNG sob demanda)
       └──▶ ScreenRecorder: AVAssetWriterInputPixelBufferAdaptor.append(pixelBuffer, pts) se gravando
```

## Criação do format description (a partir de SPS/PPS)

```swift
var formatDesc: CMVideoFormatDescription?
let status = parameterSets.withUnsafeBufferPointers { ptrs, sizes in
    CMVideoFormatDescriptionCreateFromH264ParameterSets(
        allocator: kCFAllocatorDefault,
        parameterSetCount: 2,          // SPS + PPS
        parameterSetPointers: ptrs,
        parameterSetSizes: sizes,
        nalUnitHeaderLength: 4,        // AVCC usa prefixo de 4 bytes
        formatDescriptionOut: &formatDesc)
}
```

## Sessão de decodificação

```swift
let attrs: [CFString: Any] = [
    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    kCVPixelBufferMetalCompatibilityKey: true
]
VTDecompressionSessionCreate(
    allocator: kCFAllocatorDefault,
    formatDescription: formatDesc,
    decoderSpecification: nil,
    imageBufferAttributes: attrs as CFDictionary,
    outputCallback: &callback,
    decompressionSessionOut: &session)
```

## Render: AVSampleBufferDisplayLayer

- O `CVPixelBuffer` decodificado é envolvido em um `CMSampleBuffer` (com timing) e enviado para
  uma `AVSampleBufferDisplayLayer` dentro de um `NSView` exposto ao SwiftUI via `NSViewRepresentable`.
- Aspecto preservado (aspect‑fit); rotação aplicada via transform quando `ORIENTATION` muda.
- Alternativa de baixo nível (futuro): render direto via Metal (`CAMetalLayer`) para overlays/anotações.

## Screenshot e gravação

- **Screenshot:** copia o último `CVPixelBuffer` → `CIImage` → `NSBitmapImageRep` → PNG no disco.
- **Gravação:** `AVAssetWriter` (.mov, H.264) + `AVAssetWriterInputPixelBufferAdaptor`; cada `CVPixelBuffer`
  é apendado com seu PTS. Início/fim controlados pelo usuário; arquivos salvos **localmente**.

## Latência e diagnóstico

- `PING/PONG` mede RTT; a UI mostra o indicador de latência (verde < 120 ms, amarelo < 250 ms, vermelho acima).
- Estatísticas opcionais: fps recebido, bitrate instantâneo, frames descartados.

Cuidados específicos de VideoToolbox em [09-macos-videotoolbox-cuidados.md](09-macos-videotoolbox-cuidados.md).
