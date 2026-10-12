# Funke

Schnelle Capture- und Tages-App für iOS/macOS/watchOS. Erfasse von überall in Sekunden einen
Gedanken oder eine Aufgabe (Text **oder** Sprache) und sieh + hake deine heutigen Aufgaben ab.
**Aufgaben** gehen direkt in die Inbox deiner **Zunder**-Instanz (persönliche Aufgabenverwaltung,
z. B. `https://zunder.rubeen.dev`), **Notizen** über den Relay-Server bzw. das lokale Vault nach
Obsidian. Solo-App (kein Multi-User).

- **Quick Capture** – großes Textfeld mit sofortigem Fokus, Mikrofon-Button mit deutscher Live-Transkription, optimistisches Anlegen + **Offline-Queue** (kein stiller Verlust, idempotentes Nachsenden).
- **Optionale KI-Veredelung** (Default AUS) – roher Text → Einordnung (Aufgabe vs. Notiz) + strukturierter Vorschlag *{Titel, Beschreibung}*, den du vor dem Anlegen prüfst/editierst. Vier Provider wählbar: **Apple On-Device**, **Apple Cloud (Private Cloud Compute)**, **Anthropic (Claude)**, **OpenRouter**.
- **Heute-Liste** – offene Zunder-Aufgaben (Status `open`, `in_progress`, `blocked`), fällig heute oder früher; gruppiert in **Überfällig** und **Heute**, mit Stelle (Inbox, Lose, Bereich, Projekt); abhaken setzt den Status `done`; Kontextmenü „In Zunder öffnen"; Pull-to-refresh.
- **Einstellungen** – Zunder-Server-URL + API-Token (Keychain), KI-Keys + Provider, Notiz-Relay/Vault.

> **Keine Prioritäten:** Zunder kennt keine Prioritäten, Zuständigen oder listenspezifischen Status
> (fester Ablauf: `open`, `in_progress`, `review`, `blocked`, `done`, `dropped`). Funke fragt deshalb
> weder die KI noch dich nach einer Priorität.

## Voraussetzungen

- **Xcode 27** (iOS-27-SDK). Das Projekt baut gegen das iOS-27-SDK; Deployment-Target ist **iOS 26**.
- Nur Apple-Frameworks, **keine externen Dependencies** (kein SPM/CocoaPods).
- Für die Apple-KI-Provider: ein Gerät mit aktivierter **Apple Intelligence** (im iOS-Simulator melden sich die Apple-Provider als „nicht verfügbar" – das ist erwartet; Anthropic/OpenRouter laufen auch im Simulator).

## Schnellstart

1. Projekt öffnen: `open Funke.xcodeproj`
2. **Signing-Team setzen:** Target *Funke* → *Signing & Capabilities* → dein Apple-ID-Team wählen (Bundle-ID ist `email.rubeen.funke`, bei Bedarf anpassen).
3. Auf dem Simulator starten (▶). Für ein echtes Gerät zusätzlich **Developer Mode** aktivieren (Einstellungen → Datenschutz & Sicherheit → Entwicklermodus).

Build/Tests von der Kommandozeile (Simulatornamen ggf. mit `xcrun simctl list devices` anpassen):

```bash
xcodebuild -scheme Funke -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme Funke -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Einrichtung in der App

1. **Zunder-Server-URL** in Funke → *Einstellungen → Zunder* eintragen (z. B. `https://zunder.rubeen.dev`, ohne Pfad).
2. **API-Token:** in der Zunder-Web-UI unter **Tokens** einen Token anlegen (Name z. B. `funke`, Form `zt_…`;
   er wird nur einmal angezeigt). In Funke eintragen und **Verbindung testen** – das speichert den Token im
   Schlüsselbund und zeigt den verbundenen Nutzer (`GET /api/me`). Eine Listenwahl gibt es nicht: Aufgaben
   landen immer in der Zunder-**Inbox**. In Zunders Verlauf erscheinen sie mit der Quelle `api:<Token-Name>`.
3. **Optional KI:** API-Key(s) eintragen, Provider wählen, KI-Veredelung aktivieren. Default-Provider ist **Apple On-Device** (kostenlos, privat, kein Key). OpenRouter-Default-Modell: `openai/gpt-5-nano` (in den Einstellungen änderbar). Anthropic-Modell: `claude-haiku-4-5`.

### Apple Cloud (Private Cloud Compute) aktivieren

Der Apple-Cloud-Provider nutzt Apples server-seitiges Foundation-Model auf Private Cloud Compute
(iOS 27+). Er ist im Code vollständig verdrahtet, benötigt aber das **managed Entitlement**
`com.apple.developer.private-cloud-compute`, das **Apples Freigabe** erfordert. Ohne Entitlement meldet
sich der Provider sauber als „nicht verfügbar" – die App und alle anderen Provider funktionieren normal.

Sobald dir Apple den Zugang gewährt hat:

1. Lege `Funke/Funke.entitlements` an:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>com.apple.developer.private-cloud-compute</key>
       <true/>
   </dict>
   </plist>
   ```
2. Target *Funke* → Build Settings → **Code Signing Entitlements** = `Funke/Funke.entitlements`.
3. Sicherstellen, dass dein Provisioning-Profil für dieses Entitlement berechtigt ist.

> Hinweis: Das Entitlement bewusst **nicht** im Default-Build, weil es sonst die Code-Signierung
> bricht, solange der Account nicht freigeschaltet ist.

## Architektur

MVVM mit dünnem Service-Layer; ViewModels sind über Protokolle gegen Mocks testbar.

```
Funke/
  FunkeApp.swift            @main, hält AppContainer
  AppContainer.swift        Composition-Root (verdrahtet alle Services + ViewModels)
  Models/                   EnrichmentSuggestion, TodayTask, Zunder-Modelle (Op, Entwurf, Fälligkeit),
                            PendingCapture/PendingNote/PendingItem, HapticFeedback, AppError (typisierte Fehler)
  Services/
    KeychainStore           SecretStoring (Security/Keychain)
    ZunderClient            ZunderClienting (Sync-Push + MCP filter_tasks, URLSession)
    ZunderOpFactory         UUIDv7, Knoten-ID, Hybrid Logical Clock, Aufgaben-Entwürfe
    CaptureRouter           Klassifizieren → Zunder bzw. NoteSink, Offline-Queue, Nachsenden
    OfflineQueue            OfflineQueuing (persistente JSON-Queue, actor)
    SpeechTranscriber       SpeechTranscribing (SFSpeechRecognizer de-DE + AVAudioEngine)
    AppSettings             ObservableObject (UserDefaults)
    Enrichment/
      AIEnrichmentProvider  Protokoll + EnrichmentServicing
      EnrichmentPrompt      geteilter System-Prompt, JSON-Schema, toleranter Parser
      EnrichmentService     Provider-Auswahl, nie blockierend
      AnthropicProvider · OpenRouterProvider · AppleOnDeviceProvider · AppleCloudProvider
  ViewModels/               CaptureViewModel, TodayViewModel, SettingsViewModel
  Views/                    RootView, CaptureView, EnrichmentReviewView, TodayView, SettingsView
FunkeTests/                 ZunderClient-, CaptureRouter-, Enrichment-/Parser-, OfflineQueue-Tests
```

**Grundsätze:** Secrets nur im Keychain (nie im Code/Repo/Logs). Keine `try?`-Schluckmuster, keine
Force-Unwraps an Netzgrenzen. Jeder Netzwerk-/Transkriptions-/Auth-Fehler wird sichtbar gemacht. Die KI
ist additiv und nie blockierend – schlägt sie fehl, bleibt der rohe Text anlegbar.

## Zunder-Anbindung

- **Auth:** `Authorization: Bearer zt_…` (API-Token aus dem Keychain). Bearer-Anfragen brauchen keinen
  CSRF-Header. „Verbindung testen" ruft `GET /api/me`.
- **Anlegen:** `POST /api/sync/push` mit Feld-Operationen `title`, `location` (`{"kind":"inbox"}`) und –
  falls vorhanden – `description` (Markdown). Aufgaben-ID und `op_id`s sind UUIDv7, der HLC hat das Format
  `<wall_ms 13-stellig>:<Zähler 5-stellig>:<Knoten>`; der Knoten ist `funke-` + 8 Hex-Zeichen, einmal pro
  Installation erzeugt (UserDefaults). Titel über 500 Zeichen werden gekürzt, der volle Text wandert in die
  Beschreibung.
- **Idempotenz / Offline:** Der Entwurf (ID, `op_id`s, HLCs) entsteht **vor** dem Senden. Scheitert der
  Versand vorübergehend (Netz, 408/429/5xx), wird genau dieser Entwurf gepuffert und später
  byte-identisch nachgesendet – Zunder nimmt bekannte `op_id`s ohne Wirkung erneut an, ein Timeout
  erzeugt also keine Duplikate. Lehnt Zunder Operationen ab (`rejected`, deutsche Meldung), wird nicht
  gepuffert, sondern der Fehler angezeigt; eine bereits gepufferte, abgelehnte Aufgabe wird als Notiz
  weitergepuffert, damit ihr Inhalt erhalten bleibt.
- **Migration:** Queue-Einträge aus der ClickUp-Zeit werden weiter gelesen (Titel + Beschreibung, die alte
  Priorität entfällt) und beim Nachsenden in einen frischen Zunder-Entwurf umgewandelt, der vor dem ersten
  Senden persistiert wird. Alte ClickUp-Einstellungen (Workspace/Liste) werden beim Start entfernt; den
  ClickUp-Token im Schlüsselbund nutzt Funke nicht mehr (in ClickUp widerrufen).
- **Heute:** MCP-Werkzeug `filter_tasks` über `POST /mcp` (zustandslos, ohne `initialize`):
  `due_before` = heutiger lokaler Kalendertag (inklusive), Status `open`/`in_progress`/`blocked`,
  sortiert nach Fälligkeit, höchstens 200. Fälligkeiten kommen als `JJJJ-MM-TT` oder RFC 3339 mit Offset.
  Überfällig = Fälligkeit vor dem heutigen Tagesbeginn.
- **Abhaken:** eine Operation `status = "done"`; ihr HLC liegt mindestens 1 ms über `updated_at` der
  Aufgabe, damit sie auch bei Uhrenabweichung gewinnt.
- **Link:** `<Server-URL>/#/aufgabe/<id>` öffnet die Aufgabe in der Zunder-Web-UI.

## Provider-Übersicht

| Provider            | Min iOS | Key nötig | Offline | Hinweis |
|---------------------|---------|-----------|---------|---------|
| Apple On-Device     | 26      | nein      | ja      | Apple Intelligence aktiv; im Simulator „nicht verfügbar" |
| Apple Cloud (PCC)   | 27      | nein      | nein    | managed Entitlement nötig (siehe oben) |
| Anthropic (Claude)  | –       | ja        | nein    | `claude-haiku-4-5`, structured outputs |
| OpenRouter          | –       | ja        | nein    | Default `openai/gpt-5-nano` |

## Tests & Verifikation

Unit-Tests (XCTest) decken den Zunder-Client (Request-Bau, Push-Format, HLC/UUIDv7, byte-identisches
Nachsenden, Ablehnungen, MCP-Heute-Liste inkl. Datums- und RFC-3339-Fälligkeit, Abhaken), den
CaptureRouter (Routing, Pufferung, Nachsenden inkl. ClickUp-Alteinträgen), die Offline-Queue und das
Anthropic-/OpenRouter-Parsing ab. Ausführen mit dem `xcodebuild test`-Befehl oben.

Die Foundation-Schicht (Models, Services ohne Keychain/Speech, ViewModels) samt diesen Tests wurde
zusätzlich unter Linux mit Swift 6.1 (Swift-6-Sprachmodus) gebaut und ausgeführt; der Zunder-Client
wurde außerdem gegen einen lokal gestarteten Zunder-Server Ende-zu-Ende geprüft (anlegen, identisch
nachsenden ohne Duplikat, Heute-Liste, abhaken, Ablehnung, 401). SwiftUI-Views, Keychain, Speech und
die Watch-App sind dort nicht kompilierbar und brauchen den ersten Xcode-Build.

## Falls der Simulator-Build hakt

Das Projekt wurde ohne volles Xcode erstellt (nur Command Line Tools – kein iOS-Simulator-SDK, kein
`@Generable`-Makro-Plugin). Der Großteil ist gegen das macOS-27-SDK typgecheckt und die Kernlogik wurde
ausgeführt; **nicht** lokal kompiliert werden konnten genau zwei Stellen – die einzigen wahrscheinlichen
Fehlerpunkte:

1. **Apple-Provider mit `@Generable`** (`AppleOnDeviceProvider.swift`, `AppleCloudProvider.swift`) –
   nutzen die iOS-26/27-Foundation-Models-API. Falls Xcode meckert:
   - Erwartet `LanguageModelSession(instructions:)` einen `Instructions`-Builder statt eines `String`,
     auf die Trailing-Closure-Form wechseln: `LanguageModelSession { EnrichmentPrompt.systemInstruction }`
     bzw. `LanguageModelSession(model: model) { EnrichmentPrompt.systemInstruction }`.
   - `PrivateCloudComputeLanguageModel` ist iOS-27-Beta; bei abweichenden Symbolnamen gegen Apples Doku
     *„adding-server-side-intelligence-with-private-cloud-compute"* prüfen.
2. **Test-Target** (`@testable import Funke`) – wurde geprüft, aber nicht kompiliert. Bei einem
   Mock-Signatur-Drift dem Compiler-Hinweis folgen (Mocks liegen privat in den jeweiligen Testdateien).

Alle übrigen Schichten (Models, `ZunderClient`, HTTP-Provider, Infrastruktur, ViewModels) sind
typgecheckt; pbxproj/Scheme sind validiert (Dateisystem-synchronisierte Gruppen – neue/gelöschte
Dateien brauchen keine pbxproj-Änderung).
