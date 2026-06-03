# 04 · Fluxo de captura Android

Caminho completo: **permissão → foreground service → VirtualDisplay → MediaCodec → TCP**.

## Passo a passo

```
1. MainActivity: MediaProjectionManager.createScreenCaptureIntent()
       │  (ActivityResultContracts.StartActivityForResult)
       ▼
2. Usuário concede → recebe (resultCode, dataIntent)  ← token de uso único
       │
       ▼
3. Inicia o ScreenMirrorService como foreground service
       │  startForeground(notif, FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)  ← ANTES de obter a projeção
       ▼
4. Service: MediaProjectionManager.getMediaProjection(resultCode, dataIntent)
       │  + projection.registerCallback(...)   ← obrigatório no Android 14+
       ▼
5. H264Encoder: MediaCodec.createEncoderByType("video/avc")
       │  formato: width×height, KEY_BIT_RATE, KEY_FRAME_RATE,
       │           KEY_I_FRAME_INTERVAL=1, COLOR_FormatSurface
       │  configure(format, null, null, CONFIGURE_FLAG_ENCODE) → createInputSurface()
       ▼
6. ScreenCaptureManager: projection.createVirtualDisplay(
       │     "DanteCast", width, height, densityDpi,
       │     VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, encoderInputSurface, null, null)
       ▼
7. MediaCodec.start() → loop de saída (callback assíncrono):
       │   • buffer com BUFFER_FLAG_CODEC_CONFIG  → VIDEO_CONFIG (SPS/PPS)
       │   • demais buffers                       → VIDEO_FRAME (+ flag keyframe se BUFFER_FLAG_KEY_FRAME)
       ▼
8. Packetizer (DCWP) → MirrorClient (writer único + fila) → TCP → Mac
```

## Configuração do MediaCodec (resumo)

```kotlin
val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
    setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
    setInteger(MediaFormat.KEY_BIT_RATE, bitrate)          // 2–12 Mbps (preset de qualidade)
    setInteger(MediaFormat.KEY_FRAME_RATE, fps)            // 30 (ou 60 onde suportado)
    setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)        // keyframe a cada 1 s
    setInteger(MediaFormat.KEY_BITRATE_MODE,
        MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
}
```

## Presets de qualidade (mapeamento)

| Preset | Resolução      | FPS | Bitrate alvo |
|--------|----------------|-----|--------------|
| Baixa  | 720p (escala)  | 30  | ~2–3 Mbps    |
| Média  | 1080p (escala) | 30  | ~6–8 Mbps    |
| Alta   | nativa/1080p   | 30  | ~10–12 Mbps  |

> 60fps é oferecido apenas onde o dispositivo/encoder reporta suporte.

## Orientação e mudança de resolução

- Ao detectar rotação (configuração ou `Display.rotation`), o serviço:
  1. recria o `VirtualDisplay`/encoder com as novas dimensões,
  2. re‑emite `VIDEO_CONFIG` (novos SPS/PPS),
  3. envia uma mensagem `ORIENTATION`,
  4. força um *sync frame*.
- O Mac reconstrói o `CMVideoFormatDescription` ao receber o novo `VIDEO_CONFIG`.

## Pausar / parar

- **Pausar:** parar de alimentar o encoder (ou `STREAM_STOP`) mantendo a sessão.
- **Parar (usuário):** `BYE` → tear‑down de encoder, VirtualDisplay, projeção e service.
- Ação **STOP na notificação** encerra tudo mesmo com o app em background.

## Cuidados de bateria/calor

- Bitrate e resolução configuráveis para reduzir carga.
- Encoder em modo **Surface** (zero‑copy, acelerado por hardware) — evita cópias de pixels na CPU.
- A UI mostra status de transmissão; o serviço libera recursos imediatamente ao parar.

Cuidados específicos de Android 14+ em [08-android14-cuidados.md](08-android14-cuidados.md).
