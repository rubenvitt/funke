import Foundation

/// Strukturierter KI-Vorschlag, der aus einem rohen Capture-Text entsteht.
/// Wird dem Nutzer vor dem Anlegen gezeigt und ist editierbar.
struct EnrichmentSuggestion: Equatable, Sendable {
    /// Knapper Task-Titel.
    var title: String
    /// Optionale Markdown-Beschreibung.
    var details: String?
    /// Vorgeschlagene Priorität.
    var priority: Priority

    init(title: String, details: String? = nil, priority: Priority = .normal) {
        self.title = title
        self.details = details
        self.priority = priority
    }
}
