import Foundation

/// Nicht-geheime Konfiguration für einen Capture-Vorgang (aus `AppSettings`).
struct CaptureRouterConfig: Sendable {
    var inboxListID: String?
    var noteFolder: String
    var enrichmentEnabled: Bool
    var provider: EnrichmentProviderKind
    var openRouterModel: String
}

/// Die plattformfreie Routing-Wurzel: nimmt rohen Text, klassifiziert (Task vs.
/// Notiz), veredelt und liefert das Ergebnis ans richtige Ziel (ClickUp bzw.
/// `NoteSink`) — mit Offline-Pufferung bei Transportfehlern (nie stiller Verlust).
///
/// Geteilt von App-ViewModel, App-Intent (freihändig) und Watch-Empfänger, damit
/// alle drei **dieselbe** Routing-/Queue-/Classify-Logik nutzen. Bewusst ohne UIKit/
/// SwiftUI/`@MainActor` — voll testbar gegen Mocks.
struct CaptureRouter: Sendable {
    let clickUp: ClickUpClienting
    let noteSink: NoteSink
    let queue: OfflineQueuing
    let enrichment: EnrichmentServicing

    /// Wohin das Capture ging und ob es (offline) gepuffert werden musste.
    enum Outcome: Equatable {
        case task(queued: Bool)
        case note(queued: Bool)
    }

    // MARK: - Freihändiger Pfad (Watch / App-Intent / Auto)

    /// Klassifiziert + routet ohne Review. Bei leerer Eingabe wirft er
    /// `EnrichmentError.emptyInput`; sonst liefert er, wohin es ging.
    func route(rawText: String, config: CaptureRouterConfig) async throws -> Outcome {
        let raw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw EnrichmentError.emptyInput }

        let classification = await classify(raw, config: config)
        switch classification.kind {
        case .task:
            let queued = try await deliverTask(
                title: classification.title, body: classification.body,
                priority: classification.priority, config: config
            )
            return .task(queued: queued)
        case .note:
            let queued = try await deliverNote(
                title: classification.title, body: classification.body, config: config
            )
            return .note(queued: queued)
        }
    }

    // MARK: - Bausteine (auch vom Review-Pfad der App genutzt)

    /// Klassifikation mit nie-blockierendem Fallback: KI aus/nicht verfügbar oder
    /// KI-Fehler → konservativ als Notiz (kein irrtümlicher ClickUp-Task).
    func classify(_ raw: String, config: CaptureRouterConfig) async -> CaptureClassification {
        guard config.enrichmentEnabled,
              await enrichment.availability(for: config.provider).isAvailable else {
            return Self.fallback(raw)
        }
        do {
            return try await enrichment.classify(raw, using: config.provider, openRouterModel: config.openRouterModel)
        } catch {
            return Self.fallback(raw)
        }
    }

    /// Legt einen ClickUp-Task an; bei Netzproblem → Offline-Queue. Rückgabe: gepuffert?
    func deliverTask(title: String, body: String, priority: Priority, config: CaptureRouterConfig) async throws -> Bool {
        guard let listID = config.inboxListID, !listID.isEmpty else {
            throw ClickUpError.notConfigured("keine Inbox-Liste gewählt")
        }
        let markdown = body.isEmpty ? nil : body
        do {
            try await clickUp.createTask(listID: listID, name: title, markdownDescription: markdown, priority: priority)
            return false
        } catch ClickUpError.transport {
            try await queue.enqueue(.task(PendingCapture(name: title, markdownDescription: markdown, priority: priority)))
            return true
        }
    }

    /// Schreibt eine Notiz über den `NoteSink`; bei Transportfehler → Offline-Queue.
    func deliverNote(title: String, body: String, config: CaptureRouterConfig) async throws -> Bool {
        let draft = NoteDraft(title: title, body: body, createdAt: Date())
        do {
            try await noteSink.write(draft)
            return false
        } catch let error as NoteSinkError {
            if case .transport = error {
                try await queue.enqueue(.note(PendingNote(title: title, body: body, folder: config.noteFolder)))
                return true
            }
            throw error
        }
    }

    // MARK: - Offline-Queue nachsenden

    /// Sendet alle gepufferten Items nach (Task → ClickUp, Notiz → `NoteSink`);
    /// erfolgreiche werden entfernt. Bricht bei anhaltendem Fehler ab (kein Sturm
    /// fehlschlagender Calls). Rückgabe: verbleibende Anzahl + erste Fehlermeldung.
    func flushQueue(config: CaptureRouterConfig) async -> (remaining: Int, failure: String?) {
        let items = await queue.all()
        guard !items.isEmpty else { return (0, nil) }

        var failure: String?
        loop: for item in items {
            do {
                switch item {
                case .task(let task):
                    guard let listID = config.inboxListID, !listID.isEmpty else {
                        failure = ClickUpError.notConfigured("keine Inbox-Liste").errorDescription
                        break loop
                    }
                    try await clickUp.createTask(listID: listID, name: task.name,
                                                 markdownDescription: task.markdownDescription, priority: task.priority)
                case .note(let note):
                    try await noteSink.write(note.draft)
                }
                try await queue.remove(id: item.id)
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                break loop
            }
        }

        let remaining = await queue.all().count
        return (remaining, failure)
    }

    /// Letzte Rückfalllinie (Watch/Intent): puffert den Rohtext als Notiz, falls
    /// `route` mit einem nicht-Transport-Fehler scheitert — damit ein freihändig
    /// erfasster Gedanke nie verloren geht. Wirft nicht.
    func bufferNote(rawText: String, config: CaptureRouterConfig) async {
        let raw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let title = RawTextTitle.derive(from: raw)
        try? await queue.enqueue(.note(PendingNote(
            title: title.isEmpty ? raw : title, body: raw, folder: config.noteFolder
        )))
    }

    /// Ohne KI keine echte Einordnung → konservativ Notiz mit abgeleitetem Titel + Rohtext.
    static func fallback(_ raw: String) -> CaptureClassification {
        let title = RawTextTitle.derive(from: raw)
        return CaptureClassification(kind: .note, title: title.isEmpty ? raw : title, body: raw, priority: .normal)
    }
}
