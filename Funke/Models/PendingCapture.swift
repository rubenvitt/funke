import Foundation

/// Ein lokal gepufferter Capture, der bei fehlender Verbindung gespeichert
/// und beim nächsten Start/Refresh nachgesendet wird. Niemals stiller Verlust.
struct PendingCapture: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let markdownDescription: String?
    let priority: Priority?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        markdownDescription: String? = nil,
        priority: Priority? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.markdownDescription = markdownDescription
        self.priority = priority
        self.createdAt = createdAt
    }
}
