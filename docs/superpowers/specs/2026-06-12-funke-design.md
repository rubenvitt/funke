# Funke — Design-Spec (2026-06-12)

Native iOS-App für schnelles Capture (Text + Sprache) nach ClickUp plus eine Heute-Liste. Solo-Nutzer (kein Multi-User). Schreibt **nur** nach ClickUp.

## Entschiedene Punkte

- **Stack:** SwiftUI, Swift 6 / 5.9+, durchgängig async/await. **Nur Apple-Frameworks, keine externen Dependencies** (kein SPM/CocoaPods). URLSession (Netzwerk), Security/Keychain (Secrets), Speech + AVFoundation (Transkription), FoundationModels (Apple-KI).
- **Deployment-Target iOS 26.0**, gebaut gegen das **iOS-27-SDK (Xcode 27)**. On-Device-Foundation-Models sind damit Baseline; die Apple-Cloud (Private Cloud Compute) wird mit `@available(iOS 27.0, *)` gegated.
- **Apple-Cloud direkt einkompiliert** (kein Opt-in-Flag) — Nutzer hat Xcode 27 überall. Apple-KI-Code zusätzlich in `#if canImport(FoundationModels)` für Toolchain-Portabilität.
- **Multi-Provider KI-Veredelung** über `AIEnrichmentProvider`-Protokoll: Apple On-Device, Apple Cloud (PCC), Anthropic, OpenRouter. Aktiver Provider in Settings wählbar. Default: Apple On-Device wenn verfügbar, sonst konfigurierter Cloud-Provider. KI ist **additiv, nie blockierend**.
- **KI-Capture-Flow:** Wenn KI an → jeder Capture erzeugt einen Vorschlag {Titel, Beschreibung, Priorität, optional Tag}, der vor dem Anlegen gezeigt + editierbar ist. Bei KI-Fehler bleibt der rohe Text anlegbar.
- **Heute-Liste:** mir zugewiesen, offene Status, Fälligkeit ≤ heute (nur datierte Tasks; `due_date_lt = morgen 00:00`). Überfällige optisch hervorgehoben. Nach Priorität gruppiert, nach Fälligkeit sortiert.
- **pbxproj:** Xcode-16+ „file-system-synchronized groups" (objectVersion 77), `GENERATE_INFOPLIST_FILE=YES` + `INFOPLIST_KEY_*` für Mikrofon-/Spracherkennungs-Texte. Kein separates Info.plist.
- **Bundle-ID:** `email.rubeen.funke` (Signing-Team setzt der Nutzer selbst).

## Architektur (MVVM + dünner Service-Layer)

**Models:** `Priority` (urgent/high/normal/low ↔ ClickUp 1–4), `EnrichmentSuggestion`, `TodayTask`, ClickUp-Modelle (`Team/Space/Folder/ClickUpList/ClickUpStatus`, Task-DTOs), `PendingCapture` (Offline-Queue), typisierte Fehler.

**Services (Protokoll-gemockt, ohne UI testbar):**
- `KeychainStore` (Security) — ClickUp-Token, Anthropic-Key, OpenRouter-Key.
- `ClickUpClient` (`ClickUpClienting`) — Auth `Authorization: pk_…`. getAuthorizedUser, getTeams/Spaces/Folders/Lists, createTask, getTodayTasks, getListStatuses, setTaskStatus, testConnection. Typisierter `ClickUpError`.
- KI: `AIEnrichmentProvider`-Protokoll + `EnrichmentService` (Provider-Auswahl, nie blockierend) + 4 Implementierungen (`AnthropicProvider`, `OpenRouterProvider`, `AppleOnDeviceProvider`, `AppleCloudProvider`).
- `SpeechTranscriber` — `SFSpeechRecognizer(de-DE)` + `AVAudioEngine`, Live-Transkription, Permissions.
- `OfflineQueue` — persistente JSON-Datei (Application Support), enqueue/replay, FIFO. Kein stiller Verlust.
- `AppSettings` — UserDefaults: aktiver Provider, KI an/aus, OpenRouter-Modell, gewählte Team-/Inbox-IDs.

**ViewModels (UI-frei):** `CaptureViewModel`, `TodayViewModel`, `SettingsViewModel`.

**Views:** `RootView` (TabView) · `CaptureView` + `EnrichmentReviewView` · `TodayView` · `SettingsView` + Picker-Flows.

## Datenflüsse

1. **Capture:** Feld fokussiert (Tastatur sofort) / Mic → Live-Transkript. „Erfassen": KI aus → `createTask` (optimistic clear, Haptik, Erfolg/Fehler; Netzfehler → `OfflineQueue`). KI an → `enrich()` → Review-Screen → `createTask`. Start/Refresh → Queue-Replay.
2. **Heute:** `getAuthorizedUser` → `getTodayTasks(assignee, due_date_lt, include_closed=false, order_by=due_date)` → nach Priorität gruppiert, überfällige hervorgehoben. Abhaken → Done/Closed-Status der Liste **dynamisch** (`statuses[].type ∈ {closed, done}`) → `setTaskStatus` (optimistic + Rollback). Pull-to-refresh, Empty-State.
3. **Settings:** Token → „Verbindung testen" → Workspace-/Inbox-Picker (IDs nie hart). KI-Keys + OpenRouter-Modell + Provider-Wahl + KI an/aus. Apple-Provider zeigen Verfügbarkeit.

## Fehler & Sicherheit

Typisierte Fehler überall sichtbar; keine `try?`-Schlucker, keine Force-Unwraps an Netzgrenzen. Secrets **nur** Keychain, nie geloggt/committet.

## Tests (XCTest + Mock-Clients)

ClickUpClient (Request-Bau, Prioritäts-Mapping, Done-Status-Ermittlung, due_date-Berechnung) · OfflineQueue (Puffern + Replay) · CaptureViewModel (Erfolg/Fehler/Offline/KI) · Anthropic+OpenRouter-Parsing (inkl. defekter JSON) · EnrichmentService (Provider-Auswahl). Zusätzlich eine Foundation-only-Verifikation, die hier (macOS 27 CLT) ausführbar ist.

## Verifikations-Umgebung (ehrlich)

Diese Build-Umgebung: **macOS 27, Swift 6.4, macOS-27-SDK (nur Command Line Tools)** — **kein iOS-Simulator-SDK**. Daher:
- Der finale `xcodebuild -sdk iphonesimulator`-Build läuft auf **deinem** Xcode 27.
- Hier verifizierbar: reine Foundation-Logik (ausführbar via `swift`), FoundationModels-Symbole und ein Großteil des Codes per Typecheck gegen das macOS-27-SDK; adversarialer Multi-Agent-Review als Compiler-Ersatz für iOS-spezifische Teile.

## Out of Scope (bewusst v2)

Apple-Watch-Target, direktes Obsidian-Schreiben, Push/Widgets, Multi-User, iCloud-Sync, App-Store-Polish.
