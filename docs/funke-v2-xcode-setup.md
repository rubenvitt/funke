# Funke v2 — Xcode-Setup (neue Targets)

Der gesamte Swift-/Server-Code ist geschrieben. Die **neuen Targets musst du in Xcode 27
anlegen** — Hand-Editieren der `project.pbxproj` (objectVersion 70, synthetische UUIDs)
ist für neue Targets zu riskant (eine verwaiste UUID-Referenz → Projekt öffnet nicht).
Vor dem ersten Öffnen ist alles committet; Xcode reformatiert die pbxproj beim Speichern
(erwartet, reviewbar).

## 0. Reihenfolge

1. Projekt öffnen, **iOS-App bauen** (Stufe 1+3 ist fertig verdrahtet) → testen, dass Capture/Notiz/Auto läuft.
2. App-Intent prüfen (kein neues Target nötig).
3. watchOS-Target hinzufügen.
4. macOS-Ziel hinzufügen.
5. Server aufsetzen (`server/README.md`).

## 1. App-Intent (kein Target)

`Funke/CaptureIntent.swift` liegt bereits im App-Target (synchronized group nimmt es
automatisch). Nichts zu tun außer testen:
- Build → in Kurzbefehle/Siri taucht „In Funke erfassen" auf.
- „Hey Siri, Funke Notiz" → Nachfrage „Was möchtest du festhalten?" → Diktat → gesprochene Bestätigung.
- Funktioniert freihändig über CarPlay-Siri und den Action-Button (Background-Intent, kein Entitlement).

## 2. watchOS-Target

**File → New → Target → watchOS → App** (Single-Target SwiftUI Watch App, **kein** WatchKit-Extension).
- Product Name: `FunkeWatch`
- Bundle-ID: `email.rubeen.funke.watchkitapp`
- „Embed in Companion App": Funke (iOS) auswählen → Xcode setzt `WKCompanionAppBundleIdentifier`
  + die „Embed Watch Content"-Phase automatisch.

Dann den von Xcode generierten `App.swift`/`ContentView.swift`-Platzhalter im Target durch
die fertigen Dateien ersetzen:
- Lösche die Xcode-Platzhalter im `FunkeWatch`-Gruppenordner.
- Stelle sicher, dass der `FunkeWatch/`-Ordner (mit `FunkeWatchApp.swift`,
  `WatchCaptureView.swift`, `WatchRelay.swift`) als file-system-synchronized group dem
  Watch-Target zugeordnet ist.
- **Wichtig — geteilte Datei:** `Funke/WatchCapture.swift` zusätzlich dem **Watch-Target**
  zuordnen (File Inspector → Target Membership → FunkeWatch ankreuzen). Der Watch-Sender
  braucht den Payload-Helfer.

**Capability:** In **beiden** Targets (iOS + watchOS) braucht es WatchConnectivity — das ist
ein Framework, keine Capability; einfach verfügbar. Kein App Group nötig (Sync läuft über WC).

## 3. macOS-Ziel

Zwei Wege (Empfehlung: A zum Start):

**A) Multiplatform-Destination** (geringstes Risiko): Target „Funke" → General → **Supported
Destinations** → „Mac" hinzufügen. iOS-Info-Keys sind auf macOS harmlos.

**B) Separates natives macOS-Target** (wenn du eigene Entitlements/UI willst): File → New →
Target → macOS → App, Code-Ordner teilen via Target Membership oder lokalem Package.

**App Sandbox:** Für eine **privat verteilte** (notarisierte, nicht App-Store-)App **nicht
nötig** → direkter `~/r-notes`-Zugriff. `MacVaultAccess` (NSOpenPanel + Security-Scoped
Bookmark) funktioniert mit *und* ohne Sandbox; aktivierst du die Sandbox, brauchst du das
Entitlement `com.apple.security.files.user-selected.read-write`.

Die macOS-UI: Settings hat bereits eine `#if os(macOS)`-Sektion („Vault-Ordner wählen").
`LocalFileNoteSink` schreibt dann direkt ins lokale Vault (kein Relay-Umweg).

## 4. Apple Cloud (PCC) — optional

Wie im Haupt-README: managed Entitlement `com.apple.developer.private-cloud-compute` nötig
(Apple-Freigabe). Ohne meldet sich der Provider sauber als „nicht verfügbar".

## 5. Code-Sharing (Empfehlung für später)

Wächst die Target-Zahl, lohnt ein **lokales Swift-Package `FunkeCore`** für die geteilte
Schicht (Models/Services/Router) — null pbxproj-Risiko, jedes Target referenziert es als
Dependency. Für jetzt nicht nötig: iOS-App + Watch teilen nur `WatchCapture.swift`.

## 6. Tests

`FunkeTests` enthält die portierten XCTest-Tests (`CaptureRouterTests`, `OfflineQueueTests`,
`EnrichmentTests`, `ClickUpClientTests`, `NoteEnrichmentTests`). Die maßgebliche Kern-Coverage
(61 Foundation-Logik-Tests) liegt im `.verify`-Harness (lief gegen das macOS-SDK).

```bash
xcodebuild -scheme Funke -destination 'platform=iOS Simulator,name=iPhone 17' test
```
