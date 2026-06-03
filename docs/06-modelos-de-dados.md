# 06 · Modelos de dados

Os mesmos conceitos existem nos dois lados (Swift `Codable` no Mac, `@Serializable` no Android).

## Device

| Campo             | Tipo      | Descrição                                  |
|-------------------|-----------|--------------------------------------------|
| `id`              | String    | UUID estável do dispositivo                |
| `name`            | String    | Nome amigável (ex.: "Pixel 7")             |
| `ipAddress`       | String    | Último IP conhecido                        |
| `lastConnectedAt` | DateTime? | Última conexão bem‑sucedida                |
| `trusted`         | Bool      | Dispositivo já pareado e confiável         |

## Session

| Campo        | Tipo              | Descrição                                                    |
|--------------|-------------------|--------------------------------------------------------------|
| `id`         | String            | UUID da sessão                                               |
| `deviceId`   | String            | Referência ao `Device`                                       |
| `token`      | String            | Token de pareamento (uso único)                              |
| `startedAt`  | DateTime?         | Início                                                       |
| `endedAt`    | DateTime?         | Fim                                                          |
| `resolution` | String            | Ex.: "1080x1920"                                             |
| `fps`        | Int               | 30 / 60                                                      |
| `bitrate`    | Int               | bits por segundo                                             |
| `status`     | ConnectionStatus  | `idle\|connecting\|streaming\|disconnected\|error`           |

## Recording

| Campo       | Tipo     | Descrição                          |
|-------------|----------|------------------------------------|
| `id`        | String   | UUID da gravação                   |
| `sessionId` | String   | Referência à `Session`             |
| `filePath`  | String   | Caminho do .mov local              |
| `duration`  | Int      | Duração em segundos                |
| `createdAt` | DateTime | Quando foi criada                  |

## StreamSettings (configurações de qualidade)

| Campo        | Tipo                          | Padrão     | Notas                               |
|--------------|-------------------------------|------------|-------------------------------------|
| `quality`    | enum `low\|medium\|high`      | `medium`   | preset que define bitrate/resolução |
| `resolution` | enum `p720\|p1080\|native`    | `p1080`    | escala da captura                   |
| `fps`        | Int (30/60)                   | `30`       | 60 onde suportado                   |
| `bitrate`    | Int                           | derivado   | sobrescreve o preset se definido    |

## ConnectionStatus (enum)

```
idle → listening → connecting → paired → streaming → disconnected
                                      └────────────→ error
```

## Pairing payload (QR)

```json
{ "v": 1, "ip": "192.168.0.42", "port": 7843, "token": "<token>", "name": "<mac name>" }
```

## Persistência

- **Mac:** `StreamSettings` e histórico de `Device` em `UserDefaults`/arquivo JSON em `Application Support`.
- **Android:** `StreamSettings` em `DataStore`/`SharedPreferences`.
- Gravações ficam **apenas no disco local** do Mac (requisito de segurança/privacidade).
