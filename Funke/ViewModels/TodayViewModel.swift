import Foundation
import Combine

/// Eine nach Priorität gruppierte Sektion der Heute-Liste.
struct PrioritySection: Identifiable, Equatable {
    /// `nil` = Aufgaben ohne gesetzte Priorität.
    let priority: Priority?
    let tasks: [TodayTask]

    var id: Int { priority?.rawValue ?? Int.max }

    var title: String {
        priority?.displayName ?? "Ohne Priorität"
    }
}

/// Lädt die heute fälligen/überfälligen Aufgaben und erlaubt das Abhaken.
/// Abhaken erfolgt optimistisch und rollt bei Fehlern sichtbar zurück.
@MainActor
final class TodayViewModel: ObservableObject {
    @Published var sections: [PrioritySection] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    /// True, wenn nicht geladen wird, kein Fehler vorliegt und nichts ansteht.
    var isEmpty: Bool {
        !isLoading && error == nil && sections.isEmpty
    }

    private let clickUp: ClickUpClienting
    private let settings: AppSettings
    private let calendar: Calendar
    private let now: () -> Date

    init(
        clickUp: ClickUpClienting,
        settings: AppSettings,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.clickUp = clickUp
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Laden

    func load() async {
        guard let teamID = settings.teamID, !teamID.isEmpty else {
            sections = []
            error = "Kein Workspace gewählt. Bitte in den Einstellungen einrichten."
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let user = try await clickUp.authorizedUser()
            let tasks = try await clickUp.todayTasks(
                teamID: teamID,
                assigneeID: user.id,
                now: now()
            )
            sections = Self.group(tasks, referenceDate: now(), calendar: calendar)
        } catch {
            sections = []
            self.error = Self.message(from: error)
        }
    }

    // MARK: - Abhaken (optimistisch)

    func complete(_ task: TodayTask) async {
        let snapshot = sections
        // Optimistisch entfernen.
        remove(task)
        error = nil

        guard let listID = task.listID, !listID.isEmpty else {
            sections = snapshot
            error = ClickUpError.noDoneStatus(listName: task.listName).localizedDescription
            return
        }

        do {
            let statuses = try await clickUp.listStatuses(listID: listID)
            guard let done = statuses.doneStatus() else {
                sections = snapshot
                error = ClickUpError.noDoneStatus(listName: task.listName).localizedDescription
                return
            }
            try await clickUp.setStatus(taskID: task.id, status: done.name)
        } catch {
            // Rollback bei jedem Fehler — der Nutzer sieht die Aufgabe wieder.
            sections = snapshot
            self.error = Self.message(from: error)
        }
    }

    // MARK: - Helpers

    private func remove(_ task: TodayTask) {
        sections = sections.compactMap { section in
            let remaining = section.tasks.filter { $0.id != task.id }
            guard !remaining.isEmpty else { return nil }
            return PrioritySection(priority: section.priority, tasks: remaining)
        }
    }

    /// Gruppiert nach Priorität (urgent→low, dann „ohne"), innerhalb sortiert
    /// nach Fälligkeit (überfällig zuerst, frühestes Datum zuerst).
    static func group(
        _ tasks: [TodayTask],
        referenceDate: Date,
        calendar: Calendar
    ) -> [PrioritySection] {
        let grouped = Dictionary(grouping: tasks) { $0.priority }

        let orderedKeys: [Priority?] = Priority.allCases.map { Optional($0) } + [nil]

        return orderedKeys.compactMap { key -> PrioritySection? in
            guard let bucket = grouped[key], !bucket.isEmpty else { return nil }
            let sorted = bucket.sorted { lhs, rhs in
                let lo = lhs.isOverdue(referenceDate: referenceDate, calendar: calendar)
                let ro = rhs.isOverdue(referenceDate: referenceDate, calendar: calendar)
                if lo != ro { return lo }            // Überfällige zuerst.
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?): return l < r       // Frühestes Datum zuerst.
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return lhs.name < rhs.name
                }
            }
            return PrioritySection(priority: key, tasks: sorted)
        }
    }

    private static func message(from error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
