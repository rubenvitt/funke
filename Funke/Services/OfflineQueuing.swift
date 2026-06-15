import Foundation

/// Persistente Offline-Queue für noch nicht gesendete Captures (Tasks **und** Notizen).
/// Protokollbasiert, damit der `CaptureRouter` ohne Datei-IO testbar ist.
protocol OfflineQueuing: Sendable {
    func enqueue(_ item: PendingItem) async throws
    func all() async -> [PendingItem]
    func remove(id: UUID) async throws
    func isEmpty() async -> Bool
}
