import Foundation

/// Was die Schnellerfassung anlegen soll — vom Auto-Classifier bestimmt.
enum CaptureKind: String, Codable, Equatable, Sendable, CaseIterable {
    case task
    case note
}

/// Ergebnis der kombinierten Klassifikation + Veredelung eines Roh-Captures.
/// Ein einziger KI-Aufruf liefert sowohl die Einordnung (Task vs. Notiz) als
/// auch den aufbereiteten Inhalt — der `CaptureRouter` entscheidet daraus das Ziel.
struct CaptureClassification: Equatable, Sendable {
    let kind: CaptureKind
    /// Knapper Titel (Task-Titel bzw. Notiz-Titel/Dateiname).
    let title: String
    /// Aufbereiteter Inhalt (Task-Beschreibung bzw. Notiz-Body).
    let body: String
    /// Nur bei `.task` relevant; bei `.note` ignoriert der Router sie.
    let priority: Priority

    /// Als ClickUp-Task-Vorschlag (Body wird zur Markdown-Beschreibung).
    var taskSuggestion: EnrichmentSuggestion {
        EnrichmentSuggestion(title: title, details: body.isEmpty ? nil : body, priority: priority)
    }

    /// Als Obsidian-Notiz-Vorschlag.
    var noteSuggestion: NoteSuggestion {
        NoteSuggestion(title: title, body: body)
    }
}
