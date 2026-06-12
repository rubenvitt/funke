import Foundation

/// Persistente Offline-Queue für noch nicht gesendete Captures.
/// Protokollbasiert, damit das CaptureViewModel ohne Datei-IO testbar ist.
protocol OfflineQueuing: Sendable {
    func enqueue(_ capture: PendingCapture) async throws
    func all() async -> [PendingCapture]
    func remove(id: UUID) async throws
    func isEmpty() async -> Bool
}
