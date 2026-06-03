# 03 · Fluxo de pareamento

Dois caminhos: **QR Code** (recomendado) e **código manual** (fallback). Ambos terminam no mesmo handshake DCWP.

## Fluxo por QR Code

```
MAC                                          ANDROID
───                                          ───────
1. Abre o app → tela "Parear dispositivo"
2. MirrorServer faz bind na porta 7843
3. PairingService gera token aleatório
4. Resolve IP local (getifaddrs, en0)
5. QRCodeGenerator monta o QR com:
   {v, ip, port, token, name}
   ────────────────────────────────────────▶ 6. Abre o app → "Escanear QR"
                                              7. CameraX + ML Kit lê o QR
                                              8. Parseia {ip, port, token, name}
                                              9. Conecta TCP em ip:port
              ◀──────────── HELLO(token) ─────  10. Envia HELLO com o token
11. Valida token + versão
12. Responde HELLO_ACK(accepted, settings)
              ──── HELLO_ACK ──────────────▶   13. Recebe ACK → mostra "Mac: <name>"
                                              14. Pede permissão MediaProjection
                                              15. Usuário concede
                                              16. Inicia foreground service + captura
              ◀──── VIDEO_CONFIG ───────────   17. Envia SPS/PPS
              ◀──── VIDEO_FRAME ... ─────────   18. Stream H.264 começa
19. Decodifica e exibe 🎉
```

## Fluxo manual (fallback)

```
MAC mostra: IP=192.168.0.42  Porta=7843  Código=ABC123
                  │
                  ▼
ANDROID: usuário digita IP, porta e código → conecta → HELLO(token=ABC123) → mesmo handshake
```

Útil quando a câmera não está disponível, o QR não escaneia, ou a rede tem isolamento de cliente
(nesse caso, IP manual + porta ainda funciona se o roteador permitir tráfego entre os dispositivos).

## Validações e segurança

- **Token de uso único** por sessão; expira ao desconectar. Gerado com fonte aleatória segura.
- Conexões **sem token válido** recebem `HELLO_ACK{accepted:false, reason}` e são fechadas.
- O Android **mostra o nome do Mac** (`macName`) antes de transmitir, para o usuário confirmar o destino.
- O usuário Android pode **parar a transmissão a qualquer momento** (botão STOP + ação na notificação).
- O Mac **não grava** sem ação explícita do usuário.

## Estados de erro tratados

| Situação                         | Comportamento                                                        |
|----------------------------------|----------------------------------------------------------------------|
| QR ilegível / inválido           | Mensagem "QR inválido, tente novamente" + opção manual               |
| Token incorreto                  | `HELLO_ACK{accepted:false}` → Android mostra "Pareamento recusado"   |
| Versão de protocolo incompatível | `reason="version mismatch"` → orienta atualizar o app                |
| Mac inalcançável (IP/porta)      | Timeout de conexão → "Não foi possível conectar ao Mac"              |
| Permissão de captura negada      | Volta à tela de permissão explicando por que é necessária            |
