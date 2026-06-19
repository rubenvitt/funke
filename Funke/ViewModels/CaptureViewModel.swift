import Foundation
import Combine

/// Steuert die Schnellerfassung: rohen Text aufnehmen (Tastatur oder Sprache),
/// per KI klassifizieren/veredeln und ans richtige Ziel routen — mit Offline-Pufferung.
///
/// Die eigentliche Routing-/Queue-/Classify-Logik liegt im `CaptureRouter`
/// (plattformfrei, getestet). Dieses ViewModel ist der dünne UI-Wrapper:
/// Modus-Wahl, Review-Sheet, Banner, Sprachaufnahme. KI ist **additiv, nie blockierend**.
@MainActor
final class CaptureViewModel: ObservableObject {
    /// Kurzlebige Statusmeldung über dem Eingabefeld.
    enum Banner: Equatable {
        case success(String)
        case failure(String)
    }

    /// Was die Schnellerfassung anlegt. `.auto` lässt die KI entscheiden.
    enum CaptureMode: String, CaseIterable, Identifiable {
        case auto
        case task
        case note

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto: return "Auto"
            case .task: return "Task"
            case .note: return "Notiz"
            }
        }
    }

    @Published var mode: CaptureMode = .auto
    @Published var text: String = ""
    @Published var isRecording: Bool = false
    /// Anzahl gerade im Hintergrund laufender Erfassungen (KI + Zustellung).
    /// > 0 → es wird gesendet, ohne die Eingabe zu blockieren.
    @Published var inFlight: Int = 0
    @Published var banner: Banner?
    /// Gesetzt, sobald ein KI-Task-Vorschlag zur Review/Bearbeitung ansteht (Sheet).
    @Published var review: EnrichmentSuggestion?
    /// Weitere fertige Task-Vorschläge, die warten, weil schon ein Review offen ist.
    private var reviewBacklog: [EnrichmentSuggestion] = []
    /// Anzahl der noch nicht gesendeten, lokal gepufferten Captures.
    @Published var pendingCount: Int = 0
    /// Anzahl heute erfasster Funken (für „X Funken heute").
    @Published var todaySparkCount: Int = 0
    /// Die letzten erfassten Funken (neueste zuerst) für die Liste unter dem Eingabefeld.
    @Published var recentSparks: [CapturedSpark] = []
    /// Kurzlebiger Erfolgs-Toast („Funke in Inbox erfasst"). Die View blendet ihn selbst aus.
    @Published var toast: String?
    /// Zähler, der bei jeder erfolgreichen Erfassung steigt — triggert die Funken-Animation.
    @Published var sparkBurst: Int = 0

    private let router: CaptureRouter
    private let enrichment: EnrichmentServicing
    private let settings: AppSettings
    private let queue: OfflineQueuing
    private let history: CaptureHistorying
    private let transcriber: (any SpeechTranscribing)?
    private let onHaptic: @MainActor (HapticFeedback) -> Void
    /// Verhindert paralleles/doppeltes Nachsenden (z. B. App-Start + View-Task).
    private var isFlushing = false

    init(
        router: CaptureRouter,
        enrichment: EnrichmentServicing,
        settings: AppSettings,
        queue: OfflineQueuing,
        history: CaptureHistorying,
        transcriber: (any SpeechTranscribing)?,
        onHaptic: @escaping @MainActor (HapticFeedback) -> Void = { _ in }
    ) {
        self.router = router
        self.enrichment = enrichment
        self.settings = settings
        self.queue = queue
        self.history = history
        self.transcriber = transcriber
        self.onHaptic = onHaptic
    }

    /// Lädt Funken-Zähler + jüngste Einträge aus dem lokalen Verlauf.
    func refreshHistory() async {
        todaySparkCount = await history.todayCount(now: Date())
        recentSparks = await history.recent(limit: 3)
    }

    /// Protokolliert einen erfolgreich erfassten Funken lokal und aktualisiert die Anzeige.
    private func recordSpark(_ text: String) async {
        await history.record(text: text, date: Date())
        await refreshHistory()
        sparkBurst &+= 1
    }

    // MARK: - Erfassen (asynchron, nicht-blockierend)

    /// Haupteinstieg über den „Erfassen"-Button. Leert das Eingabefeld **sofort**,
    /// damit direkt der nächste Funke getippt werden kann, und verarbeitet die
    /// Erfassung (KI + Zustellung) im Hintergrund. Mehrere Erfassungen laufen
    /// parallel; `inFlight` zählt die offenen.
    func capture() async {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        text = ""
        banner = nil
        let config = settings.routerConfig
        let mode = self.mode
        inFlight += 1
        Task { await self.process(raw, mode: mode, config: config) }
    }

    /// Hintergrund-Verarbeitung einer einzelnen Erfassung.
    private func process(_ raw: String, mode: CaptureMode, config: CaptureRouterConfig) async {
        defer { inFlight -= 1 }
        switch mode {
        case .task: await processTask(raw, config: config)
        case .note: await processNote(raw, config: config)
        case .auto: await processAuto(raw, config: config)
        }
    }

    /// `.task`: KI an + verfügbar → veredeln + Review einreihen; sonst roh anlegen.
    /// KI-Fehler sind nicht blockierend — dann geht der Roh-Task raus (kein Datenverlust).
    private func processTask(_ raw: String, config: CaptureRouterConfig) async {
        if config.enrichmentEnabled,
           await enrichment.availability(for: config.provider).isAvailable {
            do {
                let suggestion = try await enrichment.enrich(raw, using: config.provider, openRouterModel: config.openRouterModel)
                enqueueReview(suggestion)
                return
            } catch {
                onHaptic(.warning)
                // Fällt unten auf den Roh-Task zurück.
            }
        }
        await deliverTask(title: raw, body: nil, priority: nil, config: config)
    }

    /// `.note`: KI an + verfügbar → bereinigen; sonst Rohnotiz. Geht direkt raus (kein Review).
    private func processNote(_ raw: String, config: CaptureRouterConfig) async {
        var title = RawTextTitle.derive(from: raw)
        var body = raw
        if config.enrichmentEnabled,
           await enrichment.availability(for: config.provider).isAvailable {
            do {
                let suggestion = try await enrichment.enrichNote(raw, using: config.provider, openRouterModel: config.openRouterModel)
                title = suggestion.title
                body = suggestion.body
            } catch {
                // KI nie blockierend: Rohnotiz senden.
            }
        }
        await deliverNote(title: title, body: body, config: config)
    }

    /// `.auto`: klassifizieren → Task: Review einreihen; Notiz: direkt senden.
    private func processAuto(_ raw: String, config: CaptureRouterConfig) async {
        let classification = await router.classify(raw, config: config)
        switch classification.kind {
        case .task:
            enqueueReview(classification.taskSuggestion)
        case .note:
            await deliverNote(title: classification.title, body: classification.body, config: config)
        }
    }

    /// Legt den (ggf. editierten) Task-Vorschlag aus dem Review an — ebenfalls
    /// nicht-blockierend; das nächste wartende Review wird sofort gezeigt.
    func confirm(_ edited: EnrichmentSuggestion) async {
        let name = edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            banner = .failure("Titel darf nicht leer sein.")
            return
        }
        advanceReview()
        let config = settings.routerConfig
        inFlight += 1
        Task {
            await self.deliverTask(title: name, body: edited.details, priority: edited.priority, config: config)
            self.inFlight -= 1
        }
    }

    /// Verwirft das aktuelle Review und zeigt das nächste wartende (falls vorhanden).
    func cancelReview() {
        advanceReview()
    }

    /// Reiht einen fertigen Task-Vorschlag ein: zeigt ihn, oder hängt ihn hinten an,
    /// falls schon ein Review offen ist — so geht bei schneller Mehrfacherfassung keiner verloren.
    private func enqueueReview(_ suggestion: EnrichmentSuggestion) {
        if review == nil {
            review = suggestion
        } else {
            reviewBacklog.append(suggestion)
        }
    }

    /// Schaltet auf das nächste wartende Review weiter (oder schließt das Sheet).
    private func advanceReview() {
        review = reviewBacklog.isEmpty ? nil : reviewBacklog.removeFirst()
    }

    // MARK: - Zustellen (über den Router, mit Offline-Pufferung)

    private func deliverTask(title: String, body: String?, priority: Priority?, config: CaptureRouterConfig) async {
        do {
            let queued = try await router.deliverTask(
                title: title, body: body ?? "", priority: priority ?? .normal, config: config
            )
            pendingCount = await queue.all().count
            await recordSpark(title)
            toast = queued ? "Offline gepuffert" : "Funke in Inbox erfasst"
            banner = nil
            onHaptic(queued ? .warning : .success)
        } catch {
            onHaptic(.error)
            banner = .failure(Self.message(from: error))
        }
    }

    private func deliverNote(title: String, body: String, config: CaptureRouterConfig) async {
        do {
            let queued = try await router.deliverNote(title: title, body: body, config: config)
            pendingCount = await queue.all().count
            await recordSpark(title)
            toast = queued ? "Notiz offline gepuffert" : "Notiz gespeichert"
            banner = nil
            onHaptic(queued ? .warning : .success)
        } catch {
            onHaptic(.error)
            banner = .failure(Self.message(from: error))
        }
    }

    // MARK: - Offline-Queue

    /// Aktualisiert `pendingCount` aus der Queue.
    func refreshPendingCount() async {
        pendingCount = await queue.all().count
    }

    /// Sendet alle gepufferten Captures nach; erfolgreiche werden entfernt.
    func flushQueue() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        let result = await router.flushQueue(config: settings.routerConfig)
        pendingCount = result.remaining
        if let failure = result.failure {
            banner = .failure(failure)
        } else if result.remaining == 0, pendingCount == 0 {
            // Stiller Erfolg, wenn nichts mehr offen ist (keine Meldung bei leerer Queue).
        }
    }

    // MARK: - Sprachaufnahme

    /// Schaltet die Sprachaufnahme um. Partielle Ergebnisse fließen live ins Textfeld.
    func toggleRecording() async {
        guard let transcriber else {
            banner = .failure("Spracherkennung nicht verfügbar.")
            return
        }

        if isRecording {
            transcriber.stop()
            isRecording = false
            return
        }

        guard transcriber.isAvailable else {
            banner = .failure(SpeechError.recognizerUnavailable.localizedDescription)
            return
        }

        let authorized = await transcriber.requestAuthorization()
        guard authorized else {
            banner = .failure(SpeechError.notAuthorized.localizedDescription)
            return
        }

        do {
            try transcriber.start { [weak self] partial in
                Task { @MainActor in
                    self?.text = partial
                }
            }
            isRecording = true
        } catch {
            isRecording = false
            banner = .failure(Self.message(from: error))
        }
    }

    // MARK: - Helpers

    private static func message(from error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
