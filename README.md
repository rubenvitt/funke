# Funke

Schnelle Capture- und Tages-App für iOS, die mit **ClickUp** spricht. Erfasse von überall in Sekunden
einen Gedanken oder eine Aufgabe (Text **oder** Sprache) und sieh + hake deine heutigen Aufgaben ab.
Schreibt ausschließlich nach ClickUp. Solo-App (kein Multi-User).

- **Quick Capture** – großes Textfeld mit sofortigem Fokus, Mikrofon-Button mit deutscher Live-Transkription, optimistisches Anlegen + **Offline-Queue** (kein stiller Verlust).
- **Optionale KI-Veredelung** (Default AUS) – roher Text → strukturierter Vorschlag *{Titel, Beschreibung, Priorität, Tag}*, den du vor dem Anlegen prüfst/editierst. Vier Provider wählbar: **Apple On-Device**, **Apple Cloud (Private Cloud Compute)**, **Anthropic (Claude)**, **OpenRouter**.
- **Heute-Liste** – dir zugewiesen, fällig ≤ heute, offene Status; nach Priorität gruppiert, überfällige hervorgehoben; abhaken setzt den dynamisch ermittelten Erledigt-Status; Pull-to-refresh.
- **Einstellungen** – ClickUp-Token (Keychain), Workspace + Inbox-Liste per Picker, KI-Keys + Provider.

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

1. **ClickUp-Token:** ClickUp → *Settings → Apps → API Token* erzeugen (Form `pk_…`). In Funke → *Einstellungen* eintragen, **Verbindung testen**.
2. **Workspace + Inbox-Liste** per Picker wählen (IDs werden nie hart eingetragen). Captures landen in dieser Liste.
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
  Models/                   Priority, EnrichmentSuggestion, TodayTask, ClickUp-Modelle,
                            PendingCapture, HapticFeedback, AppError (typisierte Fehler)
  Services/
    KeychainStore           SecretStoring (Security/Keychain)
    ClickUpClient           ClickUpClienting (REST v2, URLSession)
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
FunkeTests/                 ClickUpClient-, Enrichment-/Parser-, OfflineQueue-, CaptureViewModel-Tests
```

**Grundsätze:** Secrets nur im Keychain (nie im Code/Repo/Logs). Keine `try?`-Schluckmuster, keine
Force-Unwraps an Netzgrenzen. Jeder Netzwerk-/Transkriptions-/Auth-Fehler wird sichtbar gemacht. Die KI
ist additiv und nie blockierend – schlägt sie fehl, bleibt der rohe Text anlegbar. Der Erledigt-Status
wird je Liste dynamisch über den Statustyp (`closed`, sonst `done`) ermittelt, nie hart angenommen.

## Provider-Übersicht

| Provider            | Min iOS | Key nötig | Offline | Hinweis |
|---------------------|---------|-----------|---------|---------|
| Apple On-Device     | 26      | nein      | ja      | Apple Intelligence aktiv; im Simulator „nicht verfügbar" |
| Apple Cloud (PCC)   | 27      | nein      | nein    | managed Entitlement nötig (siehe oben) |
| Anthropic (Claude)  | –       | ja        | nein    | `claude-haiku-4-5`, structured outputs |
| OpenRouter          | –       | ja        | nein    | Default `openai/gpt-5-nano` |

## Tests & Verifikation

Unit-Tests (XCTest) decken ClickUp-Request-Bau + Status-/Prioritäts-Mapping, Offline-Queue
(Puffern + Replay), CaptureViewModel (Erfolg/Fehler/Offline/KI) und das Anthropic-/OpenRouter-Parsing ab.
Ausführen mit dem `xcodebuild test`-Befehl oben.

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

Alle übrigen Schichten (Models, `ClickUpClient`, HTTP-Provider, Infrastruktur, ViewModels) sind gegen das
echte SDK typgecheckt; pbxproj/Scheme sind validiert.
