import Foundation

/// KI-bereinigte Notiz, die aus einem rohen oder per Sprache erfassten Text
/// entsteht. Wird vor dem Senden an Obsidian zu Titel + Markdown-Body aufbereitet.
struct NoteSuggestion: Equatable, Sendable {
    /// Knapper Titel der Notiz.
    var title: String
    /// Aufgeräumter Markdown-Body.
    var body: String
}
