# 07 · Roadmap de desenvolvimento

Desenvolvimento por fases, do protótipo provável ao produto comercial.

## Fase 0 — Protótipo 1: "os bytes chegam"
**Meta:** provar que o Android captura e envia H.264, e o Mac recebe e decodifica.
- [ ] Android: teste de `MediaProjection` + `VirtualDisplay`.
- [ ] Android: encoder `MediaCodec` H.264 → bytes Annex‑B.
- [ ] Mac: receiver TCP (`NWListener`) + `MessageReader` DCWP.
- [ ] Mac: parser de frames + `VTDecompressionSession` básico.
- ✅ **Critério:** primeiro frame decodificado aparece no log/console.

## Fase 1 — Protótipo 2: "dá pra ver"
**Meta:** viewer utilizável no Mac.
- [ ] Janela SwiftUI com `AVSampleBufferDisplayLayer`.
- [ ] Iniciar/parar conexão; render contínuo a 30fps.
- [ ] Tratamento básico de erro e desconexão.
- ✅ **Critério:** espelhamento ao vivo visível por alguns minutos.

## Fase 2 — MVP: "pareamento + experiência completa"
**Meta:** fluxo completo de pareamento e espelhamento.
- [ ] QR Code (Mac gera, Android lê) + IP/código manual.
- [ ] Foreground service Android (Android 14+ correto).
- [ ] Presets de qualidade (Baixa/Média/Alta), 720p/1080p, 30fps.
- [ ] Screenshot e gravação (`AVAssetWriter`) no Mac.
- [ ] Fullscreen + always‑on‑top.
- [ ] Indicador de latência e status de conexão.
- [ ] Builds: `DanteCast.dmg` e `DanteCast.apk`.
- ✅ **Critério:** todos os itens de aceitação (ver abaixo) passam.

## Fase 3 — Beta comercial: "bonito e confiável"
**Meta:** produto polido para criadores.
- [ ] UI/branding finais, ícone do app, onboarding.
- [ ] Telas de troubleshooting/ajuda.
- [ ] Histórico de dispositivos (`Device.trusted`).
- [ ] Reconexão graciosa quando o Wi‑Fi cai.
- [ ] Assinatura + notarização do Mac; signing do APK.

## Fase 4+ — Evolução (pós‑MVP)
- Controle remoto (ADB / Accessibility Service), clique→tap, teclado.
- Áudio.
- Descoberta automática na rede (NSD/mDNS).
- Modo de baixa latência **WebRTC** / UDP‑RTP (< 100 ms).
- USB, multi‑device, cloud relay, mini‑controlador na barra de menus.

Estratégia técnica de evolução em [10-futuro-webrtc-controle.md](10-futuro-webrtc-controle.md).

## Critérios de aceitação do MVP

- [ ] Usuário abre o app Mac e vê o QR Code.
- [ ] Usuário escaneia o QR pelo app Android.
- [ ] Android pede permissão de captura de tela.
- [ ] Após permissão, a tela do Android aparece no Mac.
- [ ] Espelha por **≥ 30 minutos** sem crashar.
- [ ] Usuário para a transmissão pelo Android.
- [ ] Usuário desconecta pelo Mac.
- [ ] Mac tira screenshot.
- [ ] Mac grava a tela espelhada.
- [ ] App lida com mudança de orientação.
- [ ] Erro claro quando a conexão falha.

## Riscos conhecidos e mitigação

| Risco                                   | Mitigação                                                       |
|-----------------------------------------|-----------------------------------------------------------------|
| Latência alta em Wi‑Fi fraca            | Controles de bitrate/resolução; degradação descartando P‑frames |
| Restrições de permissão do Android      | Uso correto de `MediaProjection` + foreground service tipado    |
| Complexidade do VideoToolbox            | Formato H.264 bem definido (DCWP) e keyframe forçado no início   |
| Limites de controle remoto              | Fora do MVP; via ADB/Accessibility depois                        |
| Variação entre fabricantes Android      | Testar cedo em Samsung, Xiaomi, Motorola, Pixel e tablets        |
