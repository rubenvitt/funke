# Funke Relay (Server)

Winziger HTTPS-Endpoint, der von Funke (iPhone/Watch/CarPlay) gesendete Notizen als
`.md`-Dateien in deinen Vault-Ordner schreibt. **`obsidian-headless`** (offizieller
Daemon) synct diesen Ordner zu Obsidian Sync und verteilt die Notiz an alle Geräte —
**du behältst Obsidian Sync**, der Mac muss nicht laufen.

```
Funke-App ──HTTPS POST /notes──►  funke-relay  ──schreibt .md──►  Vault-Ordner
                                                                       │
                                              obsidian-headless ◄──────┘ (watch + sync)
                                                    │
                                              Obsidian Sync ──► Mac / iPhone-Obsidian
```

> Kein iCloud nötig. Nur eine Sync-Methode pro Gerät — der Server nutzt
> `obsidian-headless`, dein Mac nutzt weiterhin die Desktop-App-Sync. Das sind
> verschiedene Geräte, also konfliktfrei.

## Voraussetzungen

- Linux-Server (immer an, via **Tailscale** o. ä. von unterwegs erreichbar)
- **Docker + Docker Compose**
- Obsidian-Sync-Abo (das du schon hast)

## Setup (Docker — empfohlen)

Dateien: `Dockerfile` (funke-relay), `docker-compose.yml` (funke-relay +
`obsidian-headless` via [Belphemur-Image](https://github.com/Belphemur/obsidian-headless-sync-docker)),
`.env.example`. Beide Container teilen das `./vault`-Volume und laufen als UID 1000.

```bash
cd server
cp .env.example .env            # Werte setzen (VAULT_NAME, FUNKE_TOKEN)

# 1) Auth-Token für Obsidian Sync holen (einmalig, interaktiv: E-Mail/Passwort/2FA):
docker compose run --rm --entrypoint get-token obsidian-sync
#    Ausgabe als OBSIDIAN_AUTH_TOKEN in .env eintragen.

# 2) Volume-Verzeichnisse anlegen (UID/GID 1000):
mkdir -p vault config && sudo chown -R 1000:1000 vault config

# 3) Stack starten (erster Lauf macht das ob sync-setup automatisch):
docker compose up -d
docker compose logs -f          # obsidian-sync sollte "continuous sync" zeigen
```

**Einmal verifizieren**, dass extern geschriebene Dateien hochsyncen:
```bash
echo "probe" > vault/Inbox/probe.md
# kurz warten, dann in Obsidian (Mac/iPhone) prüfen, ob "probe" auftaucht. Danach löschen.
```

> `VAULT_NAME` ist der exakte (case-sensitive) remote Vault-Name. `VAULT_PASSWORD`
> nur falls dein Vault E2E-verschlüsselt ist. `SYNC_MODE` ist `bidirectional` —
> **nicht** `mirror-remote` (das würde extern hinzugefügte Dateien wieder löschen).

## CI/CD (GitHub Actions)

Der Workflow liegt im **Repo-Root** unter `.github/workflows/docker.yml` (GitHub Actions
liest Workflows nur von dort, nicht aus Unterordnern). Er baut bei Push auf `main`/`v*`-Tags
das funke-relay-Image und pusht es nach **`ghcr.io/<dein-user>/<repo>`** (Tags: `latest`,
Branch, SemVer, SHA). `go vet`/`go build` laufen als Test (auch bei PRs). Build-Context und
Go-Befehle zeigen auf den `server/`-Ordner; getriggert wird nur bei Änderungen unter `server/`.

Auf dem Server dann das gepushte Image nutzen statt lokal zu bauen — in
`docker-compose.yml` die `build: .`-Zeile durch
`image: ghcr.io/<dein-user>/<repo>:latest` ersetzen, dann `docker compose pull && up -d`.

> Das Image ist standardmäßig privat (GHCR). Damit der Server es ziehen kann, entweder
> das Package öffentlich schalten oder `docker login ghcr.io` mit einem PAT (`read:packages`).

## Setup (manuell, ohne Docker — Alternative)

`obsidian-headless` (`npm i -g obsidian-headless`, Node 22+): `ob login` →
`ob sync-setup --vault "r-notes"` → `ob sync --continuous` (als systemd-Daemon).
funke-relay: `go build -o /usr/local/bin/funke-relay .`, dann `funke-relay.service`
(Token/Vault-Pfad anpassen) installieren. Login muss **einmal interaktiv** laufen,
bevor der Daemon startet.

## HTTPS von unterwegs (Tailscale)

Der Relay lauscht nur auf `127.0.0.1`. Tailscale stellt ihn mit **gültigem TLS-Zertifikat**
unter deinem Tailnet bereit (kein Self-signed-Problem auf iOS):

```bash
tailscale serve --bg --https=443 http://127.0.0.1:8787
tailscale serve status     # zeigt die URL, z. B. https://server.dein-tailnet.ts.net
```

## 4. In der Funke-App eintragen

Einstellungen → **Notiz-Transport (Relay)**:

- **Relay-URL:** `https://server.dein-tailnet.ts.net`
- **Relay-Token:** derselbe Wert wie `FUNKE_TOKEN`
- **Notiz-Ordner im Vault:** z. B. `Inbox`
- **„Relay testen"** → erwartet HTTP 200 von `/health`.

## API

| Methode | Pfad      | Auth                       | Zweck                              |
|---------|-----------|----------------------------|------------------------------------|
| `GET`   | `/health` | `Authorization: Bearer …`  | Erreichbarkeitstest                |
| `POST`  | `/notes`  | `Authorization: Bearer …`  | Notiz schreiben                    |

`POST /notes` Body:
```json
{ "folder": "Inbox", "filename": "2026-06-15 1430 Titel", "content": "<markdown>", "createdAt": "2026-06-15T14:30:00Z" }
```
Der Server schreibt `<vault>/<folder>/<filename>.md` atomar. `filename` ist
client-seitig sanitisiert; der Server lehnt Slashes/`..`/absolute Pfade zusätzlich ab.

## Sicherheit

- Token nur über Bearer-Header; konstante-Zeit-Vergleich. **Nie** ins Repo committen.
- Der Server hält den **entschlüsselten** Vault + Obsidian-Credentials — nur auf
  vertrauenswürdiger Maschine betreiben, Dateirechte restriktiv.
- Erreichbarkeit über Tailscale (privat), nicht öffentlich exponieren.
