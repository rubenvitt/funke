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

    /// Was die Schnellerfassung anlegt: einen ClickUp-Task oder eine Obsidian-Notiz.
    enum CaptureMode: String, CaseIterable, Identifiable {
        case task
        case note

        var id: String { rawValue }

        var title: String {
            switch self {
            case .task: return "Task"
            case .note: return "Notiz"
            }
        }
    }

    @Published var mode: CaptureMode = .task
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
    /// Öffnet eine URL (z. B. `obsidian://…`); liefert `true` bei Erfolg.
    /// Injiziert vom Composition-Root, damit das ViewModel UIKit-frei bleibt.
    private let openURL: @MainActor (URL) async -> Bool
    /// Verhindert paralleles/doppeltes Nachsenden (z. B. App-Start + View-Task).
    private var isFlushing = false

    init(
        clickUp: ClickUpClienting,
        enrichment: EnrichmentServicing,
        settings: AppSettings,
        queue: OfflineQueuing,
        transcriber: (any SpeechTranscribing)?,
        onHaptic: @escaping @MainActor (HapticFeedback) -> Void = { _ in },
        openURL: @escaping @MainActor (URL) async -> Bool = { _ in false }
    ) {
        self.clickUp = clickUp
        self.enrichment = enrichment
        self.settings = settings
        self.queue = queue
        self.transcriber = transcriber
        self.onHaptic = onHaptic
        self.openURL = openURL
    }

    // MARK: - Erfassen

    /// Haupteinstieg über den „Erfassen"-Button.
    /// KI an + Provider verfügbar → veredeln und Review zeigen.
    /// Sonst (oder bei KI-Fehler) → roh anlegen bzw. puffern.
    func capture() async {
        // Notiz-Modus zweigt komplett ab: keine KI-Veredelung, kein Puffern.
        if mode == .note {
            await captureNote()
            return
        }

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
            priority: nil
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
        await createOrQueue(
            name: name,
            markdownDescription: edited.details,
            priority: edited.priority
        )
    }

    /// Bricht eine laufende Review ab; der rohe Text bleibt im Eingabefeld.
    func cancelReview() {
        review = nil
    }

    // MARK: - Notiz an Obsidian

    /// Sendet den rohen Text als Notiz an Obsidian (`obsidian://`-URL-Schema).
    ///
    /// Grundsatz: **Notizen werden nie gepuffert.** Bei jedem Fehler bleibt der
    /// Text erhalten, damit kein Inhalt verloren geht — geleert wird nur bei Erfolg.
    private func captureNote() async {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        banner = nil

        let config = settings.obsidianConfig
        guard !config.vault.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onHaptic(.error)
            banner = .failure(ObsidianError.missingVault.errorDescription ?? "Kein Obsidian-Vault hinterlegt.")
            return
        }

        // KI an + Provider verfügbar → Rohnotiz „direkt mit KI" bereinigen.
        // KI ist nie blockierend: scheitert die Bereinigung, geht die Rohnotiz raus.
        let draft: NoteDraft
        if settings.enrichmentEnabled,
           await enrichment.availability(for: settings.activeProvider).isAvailable {
            isWorking = true
            do {
                let suggestion = try await enrichment.enrichNote(
                    raw,
                    using: settings.activeProvider,
                    openRouterModel: settings.openRouterModel
                )
                draft = NoteDraft(title: suggestion.title, body: suggestion.body, createdAt: Date())
            } catch {
                // KI nie blockierend: Rohnotiz senden.
                draft = NoteDraft(title: Self.noteTitle(from: raw), body: raw, createdAt: Date())
            }
            isWorking = false
        } else {
            draft = NoteDraft(title: Self.noteTitle(from: raw), body: raw, createdAt: Date())
        }

        let url: URL
        do {
            url = try ObsidianURLBuilder.url(for: draft, config: config)
        } catch {
            onHaptic(.error)
            banner = .failure(Self.message(from: error))
            return
        }

        let ok = await openURL(url)
        if ok {
            text = ""
            banner = .success("Notiz an Obsidian gesendet.")
            onHaptic(.success)
        } else {
            onHaptic(.error)
            banner = .failure(ObsidianError.couldNotOpen.errorDescription ?? "Obsidian konnte nicht geöffnet werden. Ist die App installiert?")
        }
    }

    /// Leitet einen knappen Titel aus dem Roh-Text ab:
    /// erste Zeile, sonst die ersten ~6 Wörter.
    private static func noteTitle(from text: String) -> String {
        let firstLine = text
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if !firstLine.isEmpty {
            return firstLine
        }
        let words = text.split(whereSeparator: { $0.isWhitespace }).prefix(6)
        return words.joined(separator: " ")
    }

    // MARK: - Anlegen / Puffern

    private func createOrQueue(
        name: String,
        markdownDescription: String?,
        priority: Priority?
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
                priority: priority
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
                    priority: priority
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
        priority: Priority?
    ) async {
        let pending = PendingCapture(
            name: name,
            markdownDescription: markdownDescription,
            priority: priority
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
                    priority: item.priority
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
