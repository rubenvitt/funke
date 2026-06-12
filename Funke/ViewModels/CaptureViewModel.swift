import Foundation
import Combine

/// Steuert die Schnellerfassung: rohen Text aufnehmen (Tastatur oder Sprache),
/// optional per KI veredeln und in ClickUp anlegen — mit Offline-Pufferung.
///
/// Grundsatz: Die KI ist **additiv und nie blockierend**. Schlägt die Veredelung
/// fehl, bleibt der rohe Text erhalten und kann jederzeit roh angelegt werden.
@MainActor
final class CaptureViewModel: ObservableObject {
    /// Kurzlebige Statusmeldung über dem Eingabefeld.
    enum Banner: Equatable {
        case success(String)
        case failure(String)
    }

    @Published var text: String = ""
    @Published var isRecording: Bool = false
    @Published var isWorking: Bool = false
    @Published var banner: Banner?
    /// Gesetzt, sobald ein KI-Vorschlag zur Review/Bearbeitung ansteht (Sheet).
    @Published var review: EnrichmentSuggestion?
    /// Anzahl der noch nicht gesendeten, lokal gepufferten Captures.
    @Published var pendingCount: Int = 0

    private let clickUp: ClickUpClienting
    private let enrichment: EnrichmentServicing
    private let settings: AppSettings
    private let queue: OfflineQueuing
    private let transcriber: (any SpeechTranscribing)?
    private let onHaptic: @MainActor (HapticFeedback) -> Void
    /// Verhindert paralleles/doppeltes Nachsenden (z. B. App-Start + View-Task).
    private var isFlushing = false

    init(
        clickUp: ClickUpClienting,
        enrichment: EnrichmentServicing,
        settings: AppSettings,
        queue: OfflineQueuing,
        transcriber: (any SpeechTranscribing)?,
        onHaptic: @escaping @MainActor (HapticFeedback) -> Void = { _ in }
    ) {
        self.clickUp = clickUp
        self.enrichment = enrichment
        self.settings = settings
        self.queue = queue
        self.transcriber = transcriber
        self.onHaptic = onHaptic
    }

    // MARK: - Erfassen

    /// Haupteinstieg über den „Erfassen"-Button.
    /// KI an + Provider verfügbar → veredeln und Review zeigen.
    /// Sonst (oder bei KI-Fehler) → roh anlegen bzw. puffern.
    func capture() async {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        banner = nil

        if settings.enrichmentEnabled {
            let availability = await enrichment.availability(for: settings.activeProvider)
            if availability.isAvailable {
                isWorking = true
                defer { isWorking = false }
                do {
                    let suggestion = try await enrichment.enrich(
                        raw,
                        using: settings.activeProvider,
                        openRouterModel: settings.openRouterModel
                    )
                    review = suggestion
                    return
                } catch {
                    // KI-Fehler ist nie blockierend: Hinweis zeigen, Text bleibt,
                    // Roh-Anlegen ist weiterhin über denselben Button möglich.
                    onHaptic(.warning)
                    banner = .failure(Self.message(from: error))
                    return
                }
            } else if let reason = availability.reason {
                // Provider gewählt, aber nicht nutzbar → sichtbarer Hinweis,
                // dann roh anlegen (KI darf die Erfassung nicht verhindern).
                banner = .failure("KI nicht verfügbar: \(reason). Lege roh an.")
            }
        }

        await createOrQueue(
            name: raw,
            markdownDescription: nil,
            priority: nil,
            tags: []
        )
    }

    /// Legt den (ggf. editierten) KI-Vorschlag als Task an.
    func confirm(_ edited: EnrichmentSuggestion) async {
        let name = edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            banner = .failure("Titel darf nicht leer sein.")
            return
        }
        review = nil
        let tags = edited.tag.map { [$0] } ?? []
        await createOrQueue(
            name: name,
            markdownDescription: edited.details,
            priority: edited.priority,
            tags: tags
        )
    }

    /// Bricht eine laufende Review ab; der rohe Text bleibt im Eingabefeld.
    func cancelReview() {
        review = nil
    }

    // MARK: - Anlegen / Puffern

    private func createOrQueue(
        name: String,
        markdownDescription: String?,
        priority: Priority?,
        tags: [String]
    ) async {
        guard let listID = settings.inboxListID, !listID.isEmpty else {
            onHaptic(.warning)
            banner = .failure("Keine Inbox-Liste konfiguriert. Bitte in den Einstellungen wählen.")
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try await clickUp.createTask(
                listID: listID,
                name: name,
                markdownDescription: markdownDescription,
                priority: priority,
                tags: tags
            )
            text = ""
            banner = .success("Aufgabe angelegt.")
            onHaptic(.success)
        } catch let error as ClickUpError {
            switch error {
            case .transport:
                // Netzproblem → lokal puffern, niemals stiller Verlust.
                await enqueueFallback(
                    name: name,
                    markdownDescription: markdownDescription,
                    priority: priority,
                    tags: tags
                )
            default:
                onHaptic(.error)
                banner = .failure(Self.message(from: error))
            }
        } catch {
            onHaptic(.error)
            banner = .failure(Self.message(from: error))
        }
    }

    private func enqueueFallback(
        name: String,
        markdownDescription: String?,
        priority: Priority?,
        tags: [String]
    ) async {
        let pending = PendingCapture(
            name: name,
            markdownDescription: markdownDescription,
            priority: priority,
            tags: tags
        )
        do {
            try await queue.enqueue(pending)
            text = ""
            pendingCount = await queue.all().count
            banner = .success("Keine Verbindung — offline gepuffert.")
            onHaptic(.warning)
        } catch {
            onHaptic(.error)
            banner = .failure("Konnte nicht puffern: \(Self.message(from: error))")
        }
    }

    /// Aktualisiert `pendingCount` aus der Queue.
    func refreshPendingCount() async {
        pendingCount = await queue.all().count
    }

    /// Sendet alle gepufferten Captures nach; erfolgreiche werden entfernt.
    func flushQueue() async {
        // Reentranz-Schutz: App-Start und View-Task können beide auslösen.
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        let items = await queue.all()
        guard !items.isEmpty else {
            pendingCount = 0
            return
        }

        guard let listID = settings.inboxListID, !listID.isEmpty else {
            pendingCount = items.count
            banner = .failure("Keine Inbox-Liste konfiguriert — gepufferte Aufgaben können nicht gesendet werden.")
            return
        }

        var failure: String?
        for item in items {
            do {
                try await clickUp.createTask(
                    listID: listID,
                    name: item.name,
                    markdownDescription: item.markdownDescription,
                    priority: item.priority,
                    tags: item.tags
                )
                try await queue.remove(id: item.id)
            } catch let error as ClickUpError {
                // Bei jedem anhaltenden Fehler (offline ODER z. B. 401) abbrechen:
                // Rest bleibt gepuffert, kein Sturm fehlschlagender Calls.
                failure = Self.message(from: error)
                break
            } catch {
                failure = Self.message(from: error)
                break
            }
        }

        pendingCount = await queue.all().count
        if let failure {
            banner = .failure(failure)
        } else if pendingCount == 0 {
            banner = .success("Alle gepufferten Aufgaben gesendet.")
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
