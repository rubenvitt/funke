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
    @Published var isWorking: Bool = false
    @Published var banner: Banner?
    /// Gesetzt, sobald ein KI-Task-Vorschlag zur Review/Bearbeitung ansteht (Sheet).
    @Published var review: EnrichmentSuggestion?
    /// Anzahl der noch nicht gesendeten, lokal gepufferten Captures.
    @Published var pendingCount: Int = 0

    private let router: CaptureRouter
    private let enrichment: EnrichmentServicing
    private let settings: AppSettings
    private let queue: OfflineQueuing
    private let transcriber: (any SpeechTranscribing)?
    private let onHaptic: @MainActor (HapticFeedback) -> Void
    /// Verhindert paralleles/doppeltes Nachsenden (z. B. App-Start + View-Task).
    private var isFlushing = false

    init(
        router: CaptureRouter,
        enrichment: EnrichmentServicing,
        settings: AppSettings,
        queue: OfflineQueuing,
        transcriber: (any SpeechTranscribing)?,
        onHaptic: @escaping @MainActor (HapticFeedback) -> Void = { _ in }
    ) {
        self.router = router
        self.enrichment = enrichment
        self.settings = settings
        self.queue = queue
        self.transcriber = transcriber
        self.onHaptic = onHaptic
    }

    // MARK: - Erfassen

    /// Haupteinstieg über den „Erfassen"-Button. Je nach Modus.
    func capture() async {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        banner = nil
        let config = settings.routerConfig

        switch mode {
        case .task: await captureTask(raw, config: config)
        case .note: await captureNote(raw, config: config)
        case .auto: await captureAuto(raw, config: config)
        }
    }

    /// `.task`: KI an + verfügbar → veredeln + Review zeigen; sonst roh anlegen.
    private func captureTask(_ raw: String, config: CaptureRouterConfig) async {
        if config.enrichmentEnabled,
           await enrichment.availability(for: config.provider).isAvailable {
            isWorking = true
            defer { isWorking = false }
            do {
                review = try await enrichment.enrich(raw, using: config.provider, openRouterModel: config.openRouterModel)
                return
            } catch {
                onHaptic(.warning)
                banner = .failure(Self.message(from: error))
                return
            }
        }
        await deliverTask(title: raw, body: nil, priority: nil, config: config)
    }

    /// `.note`: KI an + verfügbar → bereinigen; sonst Rohnotiz. Geht direkt raus (kein Review).
    private func captureNote(_ raw: String, config: CaptureRouterConfig) async {
        var title = RawTextTitle.derive(from: raw)
        var body = raw
        if config.enrichmentEnabled,
           await enrichment.availability(for: config.provider).isAvailable {
            isWorking = true
            do {
                let suggestion = try await enrichment.enrichNote(raw, using: config.provider, openRouterModel: config.openRouterModel)
                title = suggestion.title
                body = suggestion.body
            } catch {
                // KI nie blockierend: Rohnotiz senden.
            }
            isWorking = false
        }
        await deliverNote(title: title, body: body, config: config)
    }

    /// `.auto`: klassifizieren → Task: Review zeigen; Notiz: direkt senden.
    private func captureAuto(_ raw: String, config: CaptureRouterConfig) async {
        isWorking = true
        let classification = await router.classify(raw, config: config)
        isWorking = false
        switch classification.kind {
        case .task:
            review = classification.taskSuggestion
        case .note:
            await deliverNote(title: classification.title, body: classification.body, config: config)
        }
    }

    /// Legt den (ggf. editierten) Task-Vorschlag aus dem Review an.
    func confirm(_ edited: EnrichmentSuggestion) async {
        let name = edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            banner = .failure("Titel darf nicht leer sein.")
            return
        }
        review = nil
        await deliverTask(title: name, body: edited.details, priority: edited.priority, config: settings.routerConfig)
    }

    /// Bricht eine laufende Review ab; der rohe Text bleibt im Eingabefeld.
    func cancelReview() {
        review = nil
    }

    // MARK: - Zustellen (über den Router, mit Offline-Pufferung)

    private func deliverTask(title: String, body: String?, priority: Priority?, config: CaptureRouterConfig) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let queued = try await router.deliverTask(
                title: title, body: body ?? "", priority: priority ?? .normal, config: config
            )
            text = ""
            pendingCount = await queue.all().count
            banner = .success(queued ? "Keine Verbindung — offline gepuffert." : "Aufgabe angelegt.")
            onHaptic(queued ? .warning : .success)
        } catch {
            onHaptic(.error)
            banner = .failure(Self.message(from: error))
        }
    }

    private func deliverNote(title: String, body: String, config: CaptureRouterConfig) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let queued = try await router.deliverNote(title: title, body: body, config: config)
            text = ""
            pendingCount = await queue.all().count
            banner = .success(queued ? "Keine Verbindung — Notiz offline gepuffert." : "Notiz gespeichert.")
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
