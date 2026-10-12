import Foundation

/// Strukturierter KI-Vorschlag, der aus einem rohen Capture-Text entsteht.
/// Wird dem Nutzer vor dem Anlegen gezeigt und ist editierbar.
/// (Zunder kennt keine Prioritäten – deshalb nur Titel + Beschreibung.)
struct EnrichmentSuggestion: Equatable, Sendable {
    /// Knapper Task-Titel.
    var title: String
    /// Optionale Markdown-Beschreibung.
    var details: String?

    init(title: String, details: String? = nil) {
        self.title = title
        self.details = details
    }
}
