# 08 · Cuidados técnicos com Android 14+ (API 34/35)

O `MediaProjection` ficou bem mais rígido a partir do Android 14. Pontos críticos:

## 1. Foreground service tipado (obrigatório)

- Declarar a permissão **`FOREGROUND_SERVICE_MEDIA_PROJECTION`** (além de `FOREGROUND_SERVICE`).
- Declarar o serviço com **`android:foregroundServiceType="mediaProjection"`** no Manifest.
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CAMERA" /> <!-- só para o scanner de QR -->
...
<service
    android:name=".service.ScreenMirrorService"
    android:exported="false"
    android:foregroundServiceType="mediaProjection" />
```

## 2. Ordem correta: notificação ANTES da projeção

No Android 14+ é preciso **`startForeground()` com o tipo `mediaProjection` ANTES** de obter a
`MediaProjection`/criar o `VirtualDisplay`. Sequência:
1. `Activity` obtém o resultado de `createScreenCaptureIntent()` (resultCode + Intent).
2. Inicia o serviço passando esse resultado.
3. O serviço chama `startForeground(id, notification, FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)`.
4. **Só então** `mediaProjectionManager.getMediaProjection(resultCode, data)` e cria o `VirtualDisplay`.
> Inverter essa ordem lança `SecurityException` / `InvalidStateException`.

## 3. MediaProjection.Callback (obrigatório registrar)

A partir do Android 14 a projeção pode ser revogada pelo sistema/usuário. **Registrar o callback** e
parar a captura quando `onStop()` disparar — caso contrário há crash/erros.
```kotlin
projection.registerCallback(object : MediaProjection.Callback() {
    override fun onStop() { stopCaptureAndService() }
}, handler)
```
Token de captura é **de uso único**: cada nova sessão exige nova permissão.

## 4. POST_NOTIFICATIONS (API 33+)

A notificação do foreground service exige a permissão de notificações em runtime (Android 13+).
Pedir antes de iniciar o serviço; se negada, explicar que a transmissão precisa da notificação ativa.

## 5. Outras boas práticas

- **`android:enableOnBackInvokedCallback`** e edge‑to‑edge para visual moderno.
- **Densidade/orientação:** recriar o `VirtualDisplay` ao rotacionar; respeitar `densityDpi` correto.
- **Bateria/calor:** encoder em modo `Surface` (hardware), bitrate/resolução configuráveis, liberar
  recursos imediatamente no stop.
- **targetSdk 34/35:** revisar restrições de início de foreground service em background (iniciar a partir
  de uma `Activity` em foreground, nunca de um `BroadcastReceiver` arbitrário).
- **Permissão de câmera:** usada **somente** pelo scanner de QR — deixar isso explícito na UI e no Manifest.

## Checklist de release Android

- [ ] `compileSdk`/`targetSdk` ≥ 34
- [ ] Service `mediaProjection` declarado e iniciado na ordem correta
- [ ] `MediaProjection.Callback` registrado
- [ ] `POST_NOTIFICATIONS` solicitado
- [ ] Teste em Samsung/Xiaomi/Motorola/Pixel + tablet
- [ ] APK assinado (release) para distribuição
