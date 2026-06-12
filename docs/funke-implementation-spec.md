# Funke — Implementierungs-Spec (für Subagents)

Single source of truth. Der **Spine** (Modelle, Protokolle, Fehler, Settings, Prompt/Parser) ist
**bereits geschrieben** unter `Funke/Models/` und `Funke/Services/` — NICHT neu anlegen, nur konform
implementieren. Diese Datei beschreibt die noch fehlenden konkreten Typen + die verifizierten APIs.

## Konventionen (verbindlich)

- Modul `Funke`. Tests in `FunkeTests/` mit `@testable import Funke`.
- Deployment-Target **iOS 26**, Build gegen **iOS-27-SDK**. **Swift 5 language mode.**
- iOS-27-only (Apple PCC) mit `@available(iOS 27.0, macOS 27.0, *)` gaten.
- FoundationModels mit `#if canImport(FoundationModels)` umschließen; im `#else` einen Stub liefern,
  der `.unavailable(...)` meldet, damit der Composition-Root immer kompiliert.
- iOS-only (AVAudioSession/AVAudioEngine, UIKit-Haptik) mit `#if os(iOS)` gaten; im `#else` neutraler
  Pfad, damit Dateien auch gegen macOS-SDK typchecken.
- **KEINE externen Dependencies** (kein SPM/Pods). Nur Apple-Frameworks: Foundation, SwiftUI, Combine,
  Security, Speech, AVFoundation, FoundationModels.
- **KEINE Force-Unwraps an Netzgrenzen. KEIN `try?`-Schlucken. Jeder Fehler wird sichtbar** (typisierte
  Fehler aus `AppError.swift`). Secrets nur über `SecretStoring`, niemals loggen.
- **Selbstverifikation:** Nach dem Schreiben deiner Dateien `swiftc -typecheck` gegen das macOS-SDK auf
  allen Dateien, die KEINE iOS-only-Frameworks und KEINE `@Generable`-Makros brauchen. Das `@Generable`-
  Makro-Plugin fehlt in den Command Line Tools — `@Generable`-Dateien können hier NICHT typgecheckt
  werden; das ist erwartet, ehrlich benennen. Beispiel-Compile-Kommando:
  `swiftc -typecheck Funke/Models/*.swift Funke/Services/*.swift Funke/Services/Enrichment/*.swift <deine neuen Dateien>`

## Spine (vorhanden — dagegen implementieren)

```
// Models
enum Priority: Int { urgent=1, high=2, normal=3, low=4 }  // .clickUpValue, init?(clickUpValue:), .aiLabel, init?(aiLabel:), .displayName, .symbolName
struct EnrichmentSuggestion { var title: String; var details: String?; var priority: Priority; var tag: String? }
struct TodayTask { id,name:String; priority:Priority?; dueDate:Date?; statusName,statusType:String; listID,listName:String?; url:String?; func isOverdue(referenceDate:,calendar:)->Bool }
struct ClickUpUser { let id: Int; let username: String? }
struct ClickUpTeam/ClickUpSpace/ClickUpFolder/ClickUpList { let id: String; let name: String }   // Identifiable
struct ClickUpStatusInfo { let name: String; let type: String }   // [ClickUpStatusInfo].doneStatus() -> ClickUpStatusInfo?  (type "closed" sonst "done")
struct PendingCapture: Codable,Identifiable { id:UUID; name:String; markdownDescription:String?; priority:Priority?; tags:[String]; createdAt:Date }
enum HapticFeedback { success, warning, error }

// Fehler (alle LocalizedError, Equatable): ClickUpError, EnrichmentError, SpeechError, KeychainError
ClickUpError: .missingToken, .notConfigured(String), .invalidURL, .transport(String), .http(status:Int,message:String?), .decoding(String), .noDoneStatus(listName:String?)
EnrichmentError: .emptyInput, .providerUnavailable(String), .missingAPIKey(provider:String), .transport(String), .http(status:Int,message:String?), .invalidResponse(String), .unsupportedLanguage
SpeechError: .notAuthorized, .recognizerUnavailable, .audioSession(String), .noInput
KeychainError: .unexpectedStatus(Int32), .encodingFailed

// Secrets
enum SecretKey: String { clickUpToken="clickup_token", anthropicKey="anthropic_key", openRouterKey="openrouter_key" }
protocol SecretStoring: Sendable { func string(for:SecretKey)->String?; func setString(_:String?,for:SecretKey) throws; func hasValue(for:SecretKey)->Bool }  // hasValue default vorhanden

// ClickUp
protocol ClickUpClienting: Sendable {
  func authorizedUser() async throws -> ClickUpUser
  func teams() async throws -> [ClickUpTeam]
  func spaces(teamID:String) async throws -> [ClickUpSpace]
  func folders(spaceID:String) async throws -> [ClickUpFolder]
  func folderlessLists(spaceID:String) async throws -> [ClickUpList]
  func folderLists(folderID:String) async throws -> [ClickUpList]
  func createTask(listID:String, name:String, markdownDescription:String?, priority:Priority?, tags:[String]) async throws
  func todayTasks(teamID:String, assigneeID:Int, now:Date) async throws -> [TodayTask]   // + Default-Overload ohne now:
  func listStatuses(listID:String) async throws -> [ClickUpStatusInfo]
  func setStatus(taskID:String, status:String) async throws
}

// KI
enum EnrichmentProviderKind: String { appleOnDevice, appleCloud, anthropic, openRouter }  // .displayName, .requiresAPIKey, .secretKey
enum ProviderAvailability { available; unavailable(String) }  // .isAvailable, .reason
protocol AIEnrichmentProvider: Sendable { var kind:EnrichmentProviderKind {get}; func availability() async -> ProviderAvailability; func enrich(_:String) async throws -> EnrichmentSuggestion }
protocol EnrichmentServicing: Sendable { func availability(for:EnrichmentProviderKind) async -> ProviderAvailability; func enrich(_:String, using:EnrichmentProviderKind, openRouterModel:String) async throws -> EnrichmentSuggestion }
enum EnrichmentPrompt { static systemInstruction:String; static jsonSchemaString:String; static func userPrompt(for:String)->String }
enum EnrichmentResponseParser { static func parse(_ raw:String) throws -> EnrichmentSuggestion; static func extractJSONObject(from:String)->String? }  // tolerant, wirft EnrichmentError.invalidResponse

// Infra-Protokolle
protocol OfflineQueuing: Sendable { func enqueue(_:PendingCapture) async throws; func all() async -> [PendingCapture]; func remove(id:UUID) async throws; func isEmpty() async -> Bool }
@MainActor protocol SpeechTranscribing: AnyObject { var isAvailable:Bool {get}; func requestAuthorization() async -> Bool; func start(onPartialResult:@escaping (String)->Void) throws; func stop() }

// Settings (@MainActor ObservableObject)
final class AppSettings { @Published enrichmentEnabled:Bool; activeProvider:EnrichmentProviderKind; openRouterModel:String; teamID,inboxListID,inboxListName:String?; var isInboxConfigured:Bool; static defaultOpenRouterModel="openai/gpt-5-nano"; init(defaults:) }
```

---

## Verifizierte externe APIs (Stand 2026-06-12)

### ClickUp v2
- Base `https://api.clickup.com/api/v2`. Header `Authorization: <pk_token>` (KEIN „Bearer"), `Content-Type: application/json`.
- `GET /user` → `{"user":{"id":Int,"username":String?}}`. `id` (Int) ist exakt der Wert für `assignees[]`.
- `GET /team` → `{"teams":[{"id":String,"name":String}]}`.
- `GET /team/{team_id}/space?archived=false` → `{"spaces":[{id,name}]}`.
- `GET /space/{space_id}/folder?archived=false` → `{"folders":[{id,name}]}`.
- `GET /folder/{folder_id}/list?archived=false` → `{"lists":[{id,name}]}`.
- `GET /space/{space_id}/list?archived=false` → `{"lists":[{id,name}]}` (folderlose Listen).
- `POST /list/{list_id}/task` Body: `{"name":String, "markdown_content":String?, "priority":Int?, "tags":[String]?}`.
  **Markdown-Feld ist `markdown_content`** (NICHT `markdown_description`). `priority` 1=urgent…4=low; weglassen wenn nil. `status` weglassen (Liste setzt Default).
- `GET /list/{list_id}` → enthält `"statuses":[{"status":String,"type":String,"orderindex":Int,"color":String?}]`. `type ∈ {open,custom,closed,done}`. Erledigt-Status via `[ClickUpStatusInfo].doneStatus()`.
- `GET /team/{team_id}/task?assignees[]={id}&due_date_lt={ms}&include_closed=false&order_by=due_date&subtasks=false` → `{"tasks":[task]}`.
  task: `{id:String, name:String, url:String?, status:{status:String,type:String}, due_date:String?(ms-String oder null), priority:{priority:String?,id:String?}? (Objekt oder null), list:{id:String,name:String}?}`.
  **Mapping:** `due_date` String→ms→`Date(timeIntervalSince1970: ms/1000)`. `priority` über `Priority(aiLabel: prio.priority)` (Namen sind urgent/high/normal/low) sonst `prio.id`→Int→`Priority(clickUpValue:)`. `listID/listName` aus `task.list`.
- `PUT /task/{task_id}` Body `{"status":"<name>"}`.
- Fehlerkörper bei non-2xx: `{"err":String,"ECODE":String}` → `ClickUpError.http(status, message: err)`.

### Anthropic Messages (claude-haiku-4-5)
- `POST https://api.anthropic.com/v1/messages`. Header `x-api-key:<key>`, `anthropic-version:2023-06-01`, `content-type:application/json`.
- Body: `{"model":"claude-haiku-4-5","max_tokens":1024,"system":<EnrichmentPrompt.systemInstruction>,"messages":[{"role":"user","content":<rawText>}],"output_config":{"format":{"type":"json_schema","schema":<EnrichmentPrompt.jsonSchemaString als JSON-Objekt>}}}`.
  KEIN thinking/effort/temperature.
- Response `{"content":[{"type":"text","text":String}],"stop_reason":String}`. Wenn `stop_reason=="refusal"` → `EnrichmentError.invalidResponse("KI-Anfrage wurde abgelehnt")`. Sonst ersten `text`-Block via `EnrichmentResponseParser.parse`.

### OpenRouter Chat Completions
- `POST https://openrouter.ai/api/v1/chat/completions`. Header `Authorization: Bearer <key>`, `Content-Type:application/json`, optional `HTTP-Referer: https://github.com/rubeen/funke`, `X-Title: Funke`.
- Body: `{"model":<modelString>,"max_tokens":512,"messages":[{"role":"system","content":<systemInstruction>},{"role":"user","content":<rawText>}],"response_format":{"type":"json_schema","json_schema":{"name":"task","strict":true,"schema":<jsonSchemaString als Objekt>}}}`.
- Response `{"choices":[{"message":{"content":String}}]}`. `content` ist JSON-String → `EnrichmentResponseParser.parse`.
- Default-Modell `openai/gpt-5-nano`. Bei HTTP 400 (Modell ohne structured outputs) optionaler Retry mit `response_format:{"type":"json_object"}`.

### Apple On-Device (FoundationModels, iOS 26+) — `#if canImport(FoundationModels)`, `@available(iOS 26.0, macOS 26.0, *)`
```swift
import FoundationModels
@available(iOS 26.0, macOS 26.0, *)
@Generable enum DraftPriority: String { case urgent, high, normal, low }
@available(iOS 26.0, macOS 26.0, *)
@Generable struct EnrichmentDraft {
    @Guide(description: "Knapper Aufgaben-Titel") var title: String
    @Guide(description: "Beschreibung; leerer String wenn keine") var details: String
    @Guide(description: "Priorität") var priority: DraftPriority
    @Guide(description: "Ein Tag; leerer String wenn keiner") var tag: String
}
// availability(): SystemLanguageModel.default.availability → .available / .unavailable(.deviceNotEligible|.appleIntelligenceNotEnabled|.modelNotReady|let other)
//   + SystemLanguageModel.default.supportsLocale(Locale(identifier:"de")) == false → unavailable("Deutsch nicht unterstützt")
// enrich(): let s = LanguageModelSession(instructions: EnrichmentPrompt.systemInstruction)
//   let r = try await s.respond(to: rawText, generating: EnrichmentDraft.self); map r.content -> EnrichmentSuggestion (leere Strings -> nil; priority via Priority(aiLabel: r.content.priority.rawValue))
// Fehler abfangen und auf EnrichmentError mappen (unsupportedLanguageOrLocale -> .unsupportedLanguage, sonst .invalidResponse).
```
Hinweis: `details: String?`/`tag: String?` unter `@Generable` ist doku-seitig UNBESTÄTIGT — deshalb nicht-optionale `String` mit „leer = nichts" verwenden.

### Apple Cloud / Private Cloud Compute (iOS 27+) — `#if canImport(FoundationModels)`, `@available(iOS 27.0, macOS 27.0, *)`
```swift
let model = PrivateCloudComputeLanguageModel()              // neuer Typ, init()
let session = LanguageModelSession(model: model, instructions: EnrichmentPrompt.systemInstruction)
// availability(): model.availability → .available / .unavailable(.deviceNotEligible|.systemNotReady|let other)
// Guided Generation identisch (respond(to:generating:)). Netzverbindung erforderlich.
```
**Entitlement `com.apple.developer.private-cloud-compute` (managed, Apple-Freigabe) — NICHT in den Default-Build aufnehmen.** Ohne Entitlement meldet `availability` „unavailable"; der Provider degradiert sauber. README dokumentiert die Aktivierung. Falls `LanguageModelSession(model:instructions:)` nicht kompiliert, Builder-Form nutzen: `LanguageModelSession(model: model) { EnrichmentPrompt.systemInstruction }`.

---

## Zu implementierende konkrete Typen

> Test-Infrastruktur: `FunkeTests/Support/StubURLProtocol.swift` — ein `URLProtocol`, der pro Request
> kanonische `(Data, HTTPURLResponse)` liefert (Closure-Queue). Erzeuge Test-`URLSession` via
> `URLSessionConfiguration.ephemeral` + `protocolClasses = [StubURLProtocol.self]`. Alle HTTP-Clients
> akzeptieren eine injizierte `URLSession` (Default `.shared`).

### Agent A — ClickUp
- `Funke/Services/ClickUpClient.swift`: `struct ClickUpClient: ClickUpClienting`. `init(secrets: SecretStoring, session: URLSession = .shared)`. Token aus `secrets.string(for:.clickUpToken)`; nil → `ClickUpError.missingToken`. Alle Protokollmethoden gemäß „Verifizierte APIs → ClickUp". `todayTasks` baut Query: `due_date_lt = startOfDay(morgen)` in ms, `assignees[]`, `include_closed=false`, `order_by=due_date`, `subtasks=false`; mappt DTOs→`TodayTask`. Saubere `URLComponents`/`URLQueryItem`-Nutzung, non-2xx → `ClickUpError.http`, Decoding-Fehler → `ClickUpError.decoding`.
- `FunkeTests/ClickUpClientTests.swift`: Request-Bau (URL, Header `Authorization` ohne Bearer, Body-Felder inkl. `markdown_content`, Prioritäts-Int), `due_date_lt`-Berechnung (fixe `now`), Parsing der Today-Tasks (inkl. `due_date`-String, `priority`-Objekt, `list`), `setStatus`-Body, Fehler-Mapping (401/404 mit `err`).

### Agent B — KI-Provider + Service
- `Funke/Services/Enrichment/AnthropicProvider.swift`: `struct AnthropicProvider: AIEnrichmentProvider` (`kind=.anthropic`). `init(secrets:, session: = .shared, model: String = "claude-haiku-4-5")`. `availability()`: `secrets.hasValue(.anthropicKey) ? .available : .unavailable("Kein Anthropic-Schlüssel")`. `enrich`: leerer Text → `EnrichmentError.emptyInput`; Request gemäß Spec; `stop_reason`-Check; `EnrichmentResponseParser.parse`.
- `Funke/Services/Enrichment/OpenRouterProvider.swift`: analog (`kind=.openRouter`, Key `.openRouterKey`), `init(secrets:, session:, model:String)`. Request gemäß Spec, `choices[0].message.content` → parse.
- `Funke/Services/Enrichment/AppleOnDeviceProvider.swift` + `AppleCloudProvider.swift`: gemäß Apple-Spec, jeweils komplett in `#if canImport(FoundationModels) … #else <Stub, immer .unavailable> #endif`. Stub-Typen müssen ohne FoundationModels kompilieren.
- `Funke/Services/Enrichment/EnrichmentService.swift`: `struct EnrichmentService: EnrichmentServicing`. `init(secrets: SecretStoring, session: URLSession = .shared)`. Baut Provider on-demand, dispatcht `availability(for:)` und `enrich(_:using:openRouterModel:)`. OpenRouter bekommt das Modell, Anthropic den festen Modellnamen.
- `FunkeTests/EnrichmentTests.swift`: `EnrichmentResponseParser`-Tests (sauberes JSON, Code-Fences, Vor-/Nachtext, `description`-Key, fehlender Titel→Fehler, ungültige Priorität→normal); Anthropic+OpenRouter Request-Bau + Response-Parsing über `StubURLProtocol` (inkl. `stop_reason:"refusal"` → Fehler, HTTP-Fehler). Apple-Provider nur kompilieren, nicht ausführen.

### Agent C — Infrastruktur
- `Funke/Services/KeychainStore.swift`: `final class KeychainStore: SecretStoring`. `init(service: String = "email.rubeen.funke")`. Security-Framework (`kSecClassGenericPassword`, account = `SecretKey.rawValue`). `setString`: nil→löschen, sonst add/update; non-`errSecSuccess`/`errSecItemNotFound` → `KeychainError.unexpectedStatus`.
- `Funke/Services/OfflineQueue.swift`: `actor OfflineQueue: OfflineQueuing`. `init(directory: URL = <Application Support>/Funke)`. Persistiert `[PendingCapture]` als JSON (`queue.json`). enqueue/all/remove/isEmpty. Verzeichnis anlegen falls nötig.
- `Funke/Services/SpeechTranscriber.swift`: `@MainActor final class SpeechTranscriber: ObservableObject, SpeechTranscribing`. `SFSpeechRecognizer(locale: Locale(identifier:"de-DE"))` + `AVAudioEngine`. `requestAuthorization` (Mikrofon + Spracherkennung), `start(onPartialResult:)` mit `SFSpeechAudioBufferRecognitionRequest` (partielle Ergebnisse), `stop`. Audio-Teile (`AVAudioSession`, `AVAudioEngine`) unter `#if os(iOS)`; im `#else` neutraler Pfad (`isAvailable=false`, `start` wirft `SpeechError.recognizerUnavailable`) für macOS-Typecheck. Fehler → `SpeechError`.
- `FunkeTests/OfflineQueueTests.swift`: enqueue→persistiert→all liefert in Reihenfolge; Persistenz über neue Instanz auf demselben Temp-Verzeichnis; remove; isEmpty. Temp-Verzeichnis via `FileManager.default.temporaryDirectory`.

### Agent D — UI (ViewModels + Views)
ViewModels (`Funke/ViewModels/`, je `@MainActor final class … : ObservableObject`):
- `CaptureViewModel.init(clickUp: ClickUpClienting, enrichment: EnrichmentServicing, settings: AppSettings, queue: OfflineQueuing, transcriber: (any SpeechTranscribing)?, onHaptic: @escaping @MainActor (HapticFeedback) -> Void = { _ in })`.
  Published: `text`, `isRecording`, `isWorking`, `banner: Banner?` (`enum Banner { case success(String); case failure(String) }`), `review: EnrichmentSuggestion?` (Sheet), `pendingCount: Int`.
  `capture()`: leerer Text → ignorieren. Wenn `settings.enrichmentEnabled` und Provider verfügbar → `enrichment.enrich(text, using: settings.activeProvider, openRouterModel: settings.openRouterModel)` → `review = suggestion`. Bei KI-Fehler: Banner-Fehler, Text bleibt, Roh-Anlegen weiterhin möglich (Fallback-Aktion). KI aus → direkt `createOrQueue(name: text, …)`. `confirm(_ edited: EnrichmentSuggestion)`: legt Task aus dem (ggf. editierten) Vorschlag an. `createOrQueue`: `settings.inboxListID` nil → Banner „Inbox nicht konfiguriert"; sonst `clickUp.createTask(...)`; bei Transport-Fehler → `queue.enqueue(...)` + Banner „offline gepuffert"; Erfolg → Text leeren, Haptik `.success`. `toggleRecording()`. `flushQueue()`: alle `queue.all()` nachsenden, bei Erfolg `remove`.
- `TodayViewModel.init(clickUp: ClickUpClienting, settings: AppSettings)`. Published: `sections: [PrioritySection]` (`struct PrioritySection: Identifiable { priority: Priority?; tasks: [TodayTask] }`, gruppiert nach Priorität, überfällige innerhalb hervorgehoben/sortiert; nach Fälligkeit sortiert), `isLoading`, `error: String?`, `isEmpty`. `load()`: braucht `settings.teamID` + `authorizedUser().id`; ohne Team → Hinweis. `complete(_ task: TodayTask)`: optimistisch entfernen; `task.listID` → `clickUp.listStatuses` → `.doneStatus()` (nil → `ClickUpError.noDoneStatus`, Rollback) → `clickUp.setStatus`; Fehler → Rollback + sichtbarer Fehler.
- `SettingsViewModel.init(clickUp: ClickUpClienting, secrets: SecretStoring, settings: AppSettings)`. Token/Keys speichern (Keychain), `testConnection()` (→ `authorizedUser`), Workspace-Picker (`teams`), Inbox-Picker (`spaces`→`folders`/`folderlessLists`→`folderLists`), Provider-Wahl + Verfügbarkeitsanzeige (`EnrichmentService.availability(for:)`), KI-Toggle. Alles mit sichtbaren OK/Fehler-Zuständen.

Views (`Funke/Views/`): `RootView` (TabView: „Erfassen", „Heute", „Einstellungen"). `CaptureView` (großes `TextField`, `@FocusState` sofort fokussiert, Mic-Button toggelt Aufnahme, „Erfassen"-Button, Banner, `.sheet` mit `EnrichmentReviewView`). `EnrichmentReviewView` (editierbarer Titel/Beschreibung/Priorität-Picker/Tag, „Anlegen"/„Abbrechen"). `TodayView` (Liste gruppiert nach Priorität, überfällig hervorgehoben, `.refreshable`, Abhaken via Swipe/Button, Empty-State). `SettingsView` (Form: ClickUp-Token + „Verbindung testen", Workspace/Inbox-Picker, KI-Sektion mit Keys/Provider/Modell/Toggle). iOS-only-Modifier sind ok (Build läuft auf iOS-27-SDK). Haptik in der View via `UINotificationFeedbackGenerator` unter `#if os(iOS)`, an `CaptureViewModel.onHaptic` übergeben.
- `FunkeTests/CaptureViewModelTests.swift`: Erfolg (createTask aufgerufen, Text geleert, Haptik), ClickUp-Fehler (Banner, Text bleibt), Offline (Transport-Fehler → enqueue), KI-an-Pfad (enrich → review gesetzt), KI-Fehler (Banner, kein Crash). Mocks für alle Protokolle.

### Composition-Root (schreibe ICH, nicht die Subagents)
`Funke/AppContainer.swift` + `Funke/FunkeApp.swift` verdrahten `KeychainStore`, `ClickUpClient`, `EnrichmentService`, `AppSettings`, `OfflineQueue`, `SpeechTranscriber` und erzeugen die ViewModels.
