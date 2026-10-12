import Foundation

/// Nicht-geheime Konfiguration für einen Capture-Vorgang (aus `AppSettings`).
/// Die Zunder-Verbindung (Server-URL, Token) liest der `ZunderClient` selbst.
struct CaptureRouterConfig: Sendable {
    var noteFolder: String
    var enrichmentEnabled: Bool
    var provider: EnrichmentProviderKind
    var openRouterModel: String
}

/// Die plattformfreie Routing-Wurzel: nimmt rohen Text, klassifiziert (Task vs.
/// Notiz), veredelt und liefert das Ergebnis ans richtige Ziel (Zunder-Inbox bzw.
/// `NoteSink`) — mit Offline-Pufferung bei Transportfehlern (nie stiller Verlust).
///
/// Geteilt von App-ViewModel, App-Intent (freihändig) und Watch-Empfänger, damit
/// alle drei **dieselbe** Routing-/Queue-/Classify-Logik nutzen. Bewusst ohne UIKit/
/// SwiftUI/`@MainActor` — voll testbar gegen Mocks.
struct CaptureRouter: Sendable {
    let zunder: ZunderClienting
    /// Erzeugt Aufgaben-ID, `op_id`s und HLCs **vor** dem Senden, damit ein
    /// gepufferter Entwurf später byte-identisch nachgesendet werden kann.
    let drafts: ZunderOpFactory
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
                title: classification.title, body: classification.body, config: config
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
    /// KI-Fehler → konservativ als Notiz (keine irrtümliche Zunder-Aufgabe).
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

    /// Legt eine Aufgabe in der Zunder-Inbox an; bei Netzproblem → Offline-Queue
    /// mit dem bereits erzeugten Entwurf. Rückgabe: gepuffert?
    /// Abgelehnte Operationen (`ZunderError.rejected`) und Konfigurationsfehler
    /// werden geworfen, nicht gepuffert – ein Nachsenden würde nichts ändern.
    func deliverTask(title: String, body: String, config: CaptureRouterConfig) async throws -> Bool {
        let description = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : body
        let draft = drafts.makeTaskDraft(title: title, description: description)
        do {
            try await zunder.createTask(draft)
            return false
        } catch let error as ZunderError where error.isRetryable {
            try await queue.enqueue(.task(PendingCapture(title: title, description: description, draft: draft)))
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

    /// Sendet alle gepufferten Items nach (Task → Zunder, Notiz → `NoteSink`);
    /// erfolgreiche werden entfernt. Bricht bei anhaltendem Fehler ab (kein Sturm
    /// fehlschlagender Calls). Rückgabe: verbleibende Anzahl + erste Fehlermeldung.
    ///
    /// Lehnt Zunder eine gepufferte Aufgabe inhaltlich ab, würde sie die Queue
    /// dauerhaft blockieren. Sie wird dann als Notiz weitergepuffert (Inhalt bleibt
    /// erhalten) und die Ablehnung sichtbar gemeldet.
    func flushQueue(config: CaptureRouterConfig) async -> (remaining: Int, failure: String?) {
        let items = await queue.all()
        guard !items.isEmpty else { return (0, nil) }

        var failure: String?
        loop: for item in items {
            do {
                switch item {
                case .task(let task):
                    let draft = try await persistedDraft(for: task)
                    do {
                        try await zunder.createTask(draft)
                    } catch ZunderError.rejected(let message) {
                        try await queue.enqueue(.note(PendingNote(
                            title: task.title,
                            body: Self.rejectedTaskNoteBody(task),
                            folder: config.noteFolder,
                            createdAt: task.createdAt
                        )))
                        try await queue.remove(id: item.id)
                        failure = failure ?? "Aufgabe „\(task.title)“ von Zunder abgelehnt (\(message)) – als Notiz gepuffert."
                        continue loop
                    }
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

    /// Liefert den gespeicherten Entwurf. Alt-Einträge (ClickUp-Zeit, ohne Entwurf)
    /// bekommen einen frischen, der **vor** dem ersten Senden persistiert wird –
    /// so bleibt auch ihr Nachsenden idempotent.
    private func persistedDraft(for task: PendingCapture) async throws -> ZunderTaskDraft {
        if let draft = task.draft { return draft }
        let fresh = drafts.makeTaskDraft(title: task.title, description: task.description)
        try await queue.update(.task(task.withDraft(fresh)))
        return fresh
    }

    private static func rejectedTaskNoteBody(_ task: PendingCapture) -> String {
        guard let description = task.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty else {
            return task.title
        }
        return task.title + "\n\n" + description
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
        return CaptureClassification(kind: .note, title: title.isEmpty ? raw : title, body: raw)
    }
}
