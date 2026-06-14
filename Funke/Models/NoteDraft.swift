import Foundation

/// Ein roher Notiz-Entwurf für Obsidian. Im Gegensatz zu ClickUp-Captures
/// wird er nie KI-veredelt und nie lokal gepuffert — er geht direkt per
/// `obsidian://`-URL-Schema an die Obsidian-App.
struct NoteDraft: Equatable, Sendable {
    /// Kurzer Titel (erste Zeile bzw. erste Wörter des Textes).
    let title: String
    /// Vollständiger Notiz-Body.
    let body: String
    /// Erfassungszeitpunkt — fließt in den Dateinamen-Präfix ein.
    let createdAt: Date
}
