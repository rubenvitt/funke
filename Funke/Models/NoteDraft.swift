import Foundation

/// Ein Notiz-Entwurf für den Vault. Wird über einen `NoteSink` geschrieben
/// (Server-Relay bzw. lokales Dateisystem); bei Transportfehler gepuffert.
struct NoteDraft: Equatable, Sendable {
    /// Kurzer Titel (erste Zeile bzw. erste Wörter des Textes).
    let title: String
    /// Vollständiger Notiz-Body.
    let body: String
    /// Erfassungszeitpunkt — fließt in den Dateinamen-Präfix ein.
    let createdAt: Date
}
