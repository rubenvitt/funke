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
- **Node.js 22+** (für `obsidian-headless`)
- **Go 1.21+** (zum Bauen des Relays) oder ein vorgebautes Binary
- Obsidian-Sync-Abo (das du schon hast)

## 1. obsidian-headless einrichten (Vault-Sync auf dem Server)

```bash
npm install -g obsidian-headless        # Binary heißt: ob

ob login                                 # interaktiv: E-Mail + Passwort (+ 2FA)
ob sync-list-remote                      # remote Vaults auflisten
mkdir -p /srv/obsidian/vault
cd /srv/obsidian/vault
ob sync-setup --vault "r-notes" --device-name "funke-server"
# E2E-Passwort wird abgefragt (separates Sync-Verschlüsselungspasswort)

# Dauerlauf (beobachtet den Ordner, synct extern geschriebene .md hoch):
ob sync --continuous
```

Als Daemon (Beispiel-systemd-Unit `obsidian-sync.service`):

```ini
[Service]
WorkingDirectory=/srv/obsidian/vault
ExecStart=/usr/bin/ob sync --continuous
Restart=on-failure
User=DEIN_USER
[Install]
WantedBy=multi-user.target
```

> **Wichtig:** Login + `sync-setup` müssen **einmal interaktiv** (SSH) gelaufen
> sein, damit die Credentials persistiert sind, bevor der Daemon startet.
> Verifiziere einmal manuell: lege `echo test > /srv/obsidian/vault/Inbox/probe.md`
> ab und prüfe, ob die Datei in Obsidian auftaucht.

## 2. funke-relay bauen + starten

```bash
go build -o /usr/local/bin/funke-relay .

# Test (Vordergrund):
FUNKE_VAULT=/srv/obsidian/vault FUNKE_TOKEN=$(openssl rand -hex 24) FUNKE_ADDR=127.0.0.1:8787 \
  /usr/local/bin/funke-relay
```

Als Service: `funke-relay.service` anpassen (Vault-Pfad + **Token**) und installieren:

```bash
cp funke-relay.service /etc/systemd/system/
# FUNKE_TOKEN auf einen langen Zufallswert setzen (derselbe wie in der App!)
systemctl daemon-reload && systemctl enable --now funke-relay
```

## 3. HTTPS von unterwegs (Tailscale)

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
