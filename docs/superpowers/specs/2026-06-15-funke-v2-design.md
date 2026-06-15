# Funke v2 — Design-Spec (2026-06-15)

Erweitert die iOS-Capture-App (siehe `2026-06-12-funke-design.md`) um vier Stufen:
**(1)** professioneller Notiz-Transport ohne Flow-Bruch, **(2)** macOS-App, **(3)** App-Intents
+ Auto-Classifier (freihändig im Auto via Siri), **(4)** Watch-App. Alle vier teilen **ein
Rückgrat**: wie ein erfasster Gedanke in den Vault kommt und wie „Notiz vs. ClickUp" entschieden
wird. Solo-Nutzer. Reine Apple-Frameworks in den Apps (keine externen Deps); die separate
Server-Komponente darf Deps nutzen.

## Entschiedene Punkte (Brainstorming 2026-06-15)

- **Notiz-Transport = Server-Relay, kein iCloud.** Der `obsidian://`-URL-Weg (App-Wechsel,
  Flow-Bruch) entfällt vollständig. Stattdessen schreibt Funke über eine `NoteSink`-Abstraktion.
- **Obsidian Sync bleibt.** Auf dem (immer laufenden) Server hält der offizielle
  **`obsidian-headless`**-Daemon (Feb 2026, E2E-verschlüsselt) eine Vault-Kopie synchron und
  propagiert extern hinzugefügte `.md`-Dateien an alle Geräte. Kein Xvfb/Electron-Headless, kein iCloud.
- **Vault bleibt unter `~/r-notes`** auf dem Mac (lokaler Obsidian-Sync-Client). Kein Symlink nötig.
- **macOS schreibt direkt ins lokale `~/r-notes`** (Security-Scoped Bookmark) — kein Netz-Umweg,
  Obsidian Sync verteilt. iOS/Watch/Auto schreiben über den Server-Relay.
- **Classify + Enrich bleiben client-seitig** (bestehende Provider: Apple On-Device/Cloud,
  Anthropic, OpenRouter). Der Server bleibt dünn (nur Notiz-Schreiben). Watch/Auto relayen ans iPhone,
  das mit seinen Modellen klassifiziert. Secrets bleiben im Keychain, nie auf dem Server.
- **Auto = App Intents + Siri, kein CarPlay-Entitlement.** Recherche: Notiz-Apps sind keine
  genehmigte CarPlay-Kategorie; die iOS-26.4-„voice-conversational"-Kategorie braucht Apple-Einzelfall-
  Review (Chatbot-Fokus) und ist für eine private App unrealistisch. „Hey Siri, neue Funke-Notiz …"
  läuft im Auto über CarPlays Siri freihändig — derselbe Intent auch via Action-Button & Shortcuts.
- **Watch ohne Standalone-Anspruch:** relayt per WatchConnectivity ans iPhone; kein Watch-Classifier
  (watchOS hat keine allgemeine `FoundationModels`-API), kein Vault-Zugriff, keine Secrets.
- **Offline-Queue gilt jetzt auch für Notizen** (Server/Netz nicht erreichbar → puffern, nie
  stiller Verlust). Behebt die bisherige Lücke „Notizen werden nie gepuffert".
- **macOS-Deployment:** Beta 27 ist OK. Multiplatform-Target auf gemeinsamer Codebase, `#if os(...)`.

---

## Stufe 1 — Notiz-Transport (Fundament)

### NoteSink (neu)
```swift
protocol NoteSink: Sendable { func write(_ draft: NoteDraft) async throws }
```
- **`RelayNoteSink`** (iOS, watchOS-Relay-Ziel ist iPhone): `POST https://<server>/notes`,
  Header `Authorization: Bearer <token>` (Keychain), JSON-Body `{title, body, folder, createdAt}`.
  Typisierte Fehler; `transport`-Fehler → Queue (analog `ClickUpError.transport`).
- **`LocalFileNoteSink`** (macOS): schreibt atomar (`temp + rename`) nach
  `<vaultRoot>/<folder>/<name>.md`. `vaultRoot` via Security-Scoped Bookmark (einmalige `NSOpenPanel`-Wahl).
- Dateiname-Logik (`sanitizedFileName`, Zeitstempel-Präfix, illegale Zeichen) wird aus
  `ObsidianURLBuilder` herausgelöst in einen geteilten `NoteFileName`-Helper (rein/testbar).

### Offline-Queue erweitern
- `OfflineQueue` wird generisch über ein **`PendingItem`-Enum**: `.task(PendingTask)` | `.note(PendingNote)`.
  `PendingTask` = bisheriges `PendingCapture`. `PendingNote` = `{title, body, folder, createdAt, id}`.
- Migration: bestehende reine `[PendingCapture]`-JSON-Datei tolerant einlesen (als `.task` mappen).
- `flushQueue` routet je Variante: `.task` → `ClickUpClient.createTask`, `.note` → `NoteSink.write`.
  Abbruch bei anhaltendem Fehler (kein Sturm), FIFO, persistente JSON-Datei (Application Support).

### CaptureViewModel-Umbau
- `captureNote()` ruft `noteSink.write(draft)` statt `openURL(obsidian://…)`. Bei `transport`-Fehler
  → `queue.enqueue(.note(...))` + Banner „offline gepuffert". Erfolg → Feld leeren, Haptik, Banner.
- `openURL`-Closure für Notizen entfällt; `NoteSink` wird vom `AppContainer` injiziert (plattformabhängig).

### Settings-Änderungen
- **Entfällt:** `obsidianVault`, `obsidianInboxFolder`-as-URL, `obsidianNoteTarget`,
  `obsidianUseAdvancedURI` (und `ObsidianURLBuilder`/`ObsidianConfig`/`ObsidianURLBuilderTests`).
- **Neu (iOS):** `relayBaseURL` (UserDefaults) + Relay-Token (Keychain, neuer `SecretKey.relayToken`).
- **Neu (macOS):** Vault-Bookmark (UserDefaults, Security-Scoped) + Ziel-`folder`.
- `folder` (vault-relativer Inbox-Ordner, Default „Inbox") bleibt für beide Sinks erhalten.

### Server-Komponente (separates Repo/Verzeichnis, nicht im App-Target)
- `obsidian-headless`-Daemon (Container/systemd) synct `<vaultRoot>` mit Obsidian Sync.
- **Mini-HTTPS-Endpoint:** `POST /notes` (Bearer-Auth), validiert, schreibt
  `<vaultRoot>/<folder>/<sanitizedName>.md` atomar; `GET /health`. Idempotenz über `createdAt`-Präfix +
  Dedup bei identischem Inhalt. Erreichbarkeit via **Tailscale** (zu bestätigen). Sprachwahl
  (Go-Single-Binary vs. Swift/Hummingbird) bei Implementierung der Stufe entschieden.

### Tests (Stufe 1)
`NoteFileName` (Sanitizing/Präfix/Kürzung), `RelayNoteSink` (Request-Bau + Fehler-Mapping via
`StubURLProtocol`), `OfflineQueue` (Task+Note puffern/replay, Migration alter Datei),
`CaptureViewModel.captureNote` (Erfolg/Transportfehler→Queue/Sink-Fehler).

---

## Stufe 2 — macOS-App

- Gemeinsame Codebase als **Multiplatform-Target** (objectVersion-77-pbxproj, file-system-synchronized
  groups; macOS-Destination ergänzen). `#if os(macOS)`-Pfade für die wenigen UIKit-Stellen
  (`AppContainer` hat sie bereits: `openURL`, Haptik).
- `AppContainer` injiziert auf macOS `LocalFileNoteSink`; einmalige Ordnerwahl per `NSOpenPanel`
  → Security-Scoped Bookmark in Settings.
- Views weitgehend wiederverwendet; `RootView` `TabView` → auf macOS ggf. `NavigationSplitView`.
  Haptik no-op auf macOS. Spracheingabe (`SpeechTranscriber`) plattform-gegated.
- Tests: `LocalFileNoteSink` (atomares Schreiben in temporäres Verzeichnis), Settings-Bookmark-Roundtrip.

---

## Stufe 3 — App Intents + Auto-Classifier

### Classifier
- **`EnrichmentService.classify(_:)`** → `ClassificationResult { kind: .task | .note,
  task: EnrichmentSuggestion?, note: NoteSuggestion? }`. Ein kombinierter Call (kind + passender
  Inhalt) spart einen Roundtrip. Prompt/Schema in neuem `ClassifyPrompt` (HTTP-Provider: JSON-Schema
  mit `kind`-Enum; Apple-Provider: `@Generable` mit Enum-Feld). Additiv, nie blockierend: bei
  Klassifikations-Fehler Fallback auf den manuell gewählten Modus.

### App Intent
- **`CaptureIntent`** (`AppIntent`, `openAppWhenRun = false`): Parameter `text` (von Siri-Diktat
  resolved). Ablauf: `classify` → route (`.note` → `NoteSink`, `.task` → `ClickUpClient`) → bei
  Netz-/Server-Fehler → `OfflineQueue`. **Kein Review-Screen** (freihändig); Rückgabe als
  `IntentResult & ProvidesDialog` mit Sprach-Feedback („Als Notiz gespeichert." / „Aufgabe angelegt.").
- `AppShortcutsProvider` mit deutschen Phrasen („Funke erfassen", „neue Funke-Notiz").
  Funktioniert über CarPlays Siri, Action-Button und Shortcuts — ohne CarPlay-Entitlement.
- Der Intent teilt sich die Service-Schicht mit der App (gemeinsamer „Capture-Router", extrahiert aus
  `CaptureViewModel`, damit Intent und ViewModel dieselbe Routing-/Queue-Logik nutzen).

### In-App
- Capture-Toggle bekommt einen **„Auto"-Modus** (Default wählbar): Classifier entscheidet, das Ergebnis
  ist im Review-Screen umschaltbar (Task ↔ Notiz), bevor es rausgeht.

### Tests
`classify`-Parsing (Task/Notiz/defektes JSON → Fallback), `CaptureRouter` (Routing + Queue-Fallback),
App-Intent-Logik gegen Mock-Services (Foundation-only ausführbar).

---

## Stufe 4 — Watch-App

- **watchOS-Target.** Quick-Capture-UI: großer Diktat-Button (Sprache primär; native Texteingabe als
  Sekundärweg). Minimaler Zustand: aufnehmen → Bestätigung.
- Rohtext → **`WCSession.transferUserInfo([...])`** (garantierte, queue-basierte Zustellung, auch wenn
  das iPhone gerade nicht aktiv ist). Payload `{rawText, createdAt, source: "watch"}`.
- **iPhone** empfängt (`WCSessionDelegate`, auch im Hintergrund), führt denselben `CaptureRouter`
  aus (classify → route → ggf. Queue). Optional: Bestätigung (`kind`) via `transferUserInfo` zurück.
- Watch hält **keine** Secrets, keinen Classifier, keinen Vault-Zugriff.
- Tests: Payload-Kodierung, iPhone-seitige Empfangs-→Router-Verdrahtung gegen Mocks.

---

## Abhängigkeiten & Reihenfolge

1 (Fundament) → dann 3 (Classifier/Router, den 4 braucht) → 2 (macOS, unabhängig von 3) → 4 (Watch,
braucht 3). `CaptureRouter` (aus Stufe 1/3) ist die geteilte Wurzel für App, Intent und Watch-Empfang.

## Fehler & Sicherheit

Typisierte Fehler überall sichtbar; keine `try?`-Schlucker, keine Force-Unwraps an Netz-/FS-Grenzen.
Relay-Token + ClickUp-/KI-Keys **nur** Keychain, nie geloggt/committet. TLS zum Server (Tailscale +
echtes oder Tailscale-cert; Self-signed nur mit explizitem Pinning, kein blindes Skippen).

## Verifikations-Umgebung (ehrlich)

Diese Umgebung: **macOS 27, nur Command Line Tools — kein iOS-/watchOS-Simulator-SDK**. Daher:
- Hier verifizierbar: reine Foundation-Logik (ausführbar via `swift`), Typecheck gegen das macOS-27-SDK,
  adversarialer Multi-Agent-Review als Compiler-Ersatz für iOS/watchOS-spezifische Teile.
- Der finale `xcodebuild`-Build für iOS/watchOS läuft auf **deinem** Xcode 27. App-Intents-,
  WatchConnectivity- und PrivateCloudCompute-Symbole gegen Apples aktuelle Doku gegengeprüft.

## Out of Scope (bewusst)

Standalone-Cellular-Watch ohne iPhone; CarPlay-Template-App; Server-seitige KI/Routing; Multi-User;
iCloud; bidirektionale Vault-Synchronisation (Funke schreibt, liest nicht zurück); App-Store-Polish.
