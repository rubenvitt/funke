import Foundation

/// Persistente Offline-Queue für noch nicht gesendete Captures (Tasks **und** Notizen).
/// Protokollbasiert, damit der `CaptureRouter` ohne Datei-IO testbar ist.
protocol OfflineQueuing: Sendable {
    func enqueue(_ item: PendingItem) async throws
    func all() async -> [PendingItem]
    func remove(id: UUID) async throws
    /// Ersetzt ein vorhandenes Element (gleiche `id`) an seiner Position, z. B. um
    /// einem Alt-Eintrag vor dem Senden seinen Zunder-Entwurf mitzugeben.
    /// Unbekannte `id` → keine Änderung (das Element wurde inzwischen entfernt).
    func update(_ item: PendingItem) async throws
    func isEmpty() async -> Bool
}
