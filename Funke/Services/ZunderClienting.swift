import Foundation

/// Schnittstelle zu Zunder (Sync-API + MCP). Bewusst protokollbasiert, damit
/// Router und ViewModels gegen Mocks getestet werden können.
protocol ZunderClienting: Sendable {
    /// Der zum Token gehörende Nutzer (`GET /api/me`). Dient als „Verbindung testen".
    func currentUser() async throws -> ZunderUser

    /// Legt eine vorbereitete Aufgabe an (`POST /api/sync/push`). Sendet exakt
    /// die Operationen des Entwurfs – Wiederholungen sind dadurch idempotent.
    /// Abgelehnte Operationen → `ZunderError.rejected` mit Server-Meldung.
    func createTask(_ draft: ZunderTaskDraft) async throws

    /// Heute fällige / überfällige, offene Aufgaben (MCP `filter_tasks`).
    func todayTasks(now: Date) async throws -> [TodayTask]

    /// Setzt eine Aufgabe auf `done`. `notBefore` (bekannter Server-Stand der
    /// Aufgabe) hebt den HLC darüber, damit die Änderung sicher gewinnt.
    func completeTask(id: String, notBefore: Date?) async throws
}

extension ZunderClienting {
    /// Komfort-Default: Standardisiert auf „jetzt".
    func todayTasks() async throws -> [TodayTask] {
        try await todayTasks(now: Date())
    }
}
