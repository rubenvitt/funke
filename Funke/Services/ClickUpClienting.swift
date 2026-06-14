import Foundation

/// Schnittstelle zur ClickUp-REST-API v2. Bewusst protokollbasiert, damit
/// ViewModels gegen Mocks getestet werden können.
protocol ClickUpClienting: Sendable {
    /// Der zum Token gehörende Nutzer (GET /user). Dient auch als „Verbindung testen".
    func authorizedUser() async throws -> ClickUpUser

    func teams() async throws -> [ClickUpTeam]
    func spaces(teamID: String) async throws -> [ClickUpSpace]
    func folders(spaceID: String) async throws -> [ClickUpFolder]
    func folderlessLists(spaceID: String) async throws -> [ClickUpList]
    func folderLists(folderID: String) async throws -> [ClickUpList]

    /// Legt eine Aufgabe in der Inbox-Liste an.
    func createTask(
        listID: String,
        name: String,
        markdownDescription: String?,
        priority: Priority?
    ) async throws

    /// Heute fällige / überfällige, offene, mir zugewiesene Aufgaben.
    func todayTasks(teamID: String, assigneeID: Int, now: Date) async throws -> [TodayTask]

    /// Erlaubte Status einer Liste (für die dynamische Erledigt-Ermittlung).
    func listStatuses(listID: String) async throws -> [ClickUpStatusInfo]

    /// Setzt den Status einer Aufgabe (PUT /task/{id}).
    func setStatus(taskID: String, status: String) async throws
}

extension ClickUpClienting {
    /// Komfort-Default: Standardisiert auf „jetzt".
    func todayTasks(teamID: String, assigneeID: Int) async throws -> [TodayTask] {
        try await todayTasks(teamID: teamID, assigneeID: assigneeID, now: Date())
    }
}
