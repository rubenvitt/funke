import Foundation

/// Eine lokal gepufferte Notiz, die bei fehlender Server-/Netzverbindung
/// gespeichert und beim nächsten Start/Refresh nachgesendet wird.
/// Niemals stiller Verlust — das Pendant zu `PendingCapture` (ClickUp-Tasks).
struct PendingNote: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let body: String
    /// Vault-relativer Zielordner (z. B. „Inbox").
    let folder: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        folder: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.folder = folder
        self.createdAt = createdAt
    }

    /// Wertgleicher `NoteDraft` für die Übergabe an einen `NoteSink`.
    var draft: NoteDraft {
        NoteDraft(title: title, body: body, createdAt: createdAt)
    }
}
