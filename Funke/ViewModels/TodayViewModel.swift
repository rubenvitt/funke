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

/// Lädt die heute fälligen/überfälligen Aufgaben und erlaubt das Abhaken sowie
/// das Verschieben von Fokus-Blöcken auf der Timeline. Abhaken erfolgt optimistisch
/// und rollt bei Fehlern sichtbar zurück; erledigte Aufgaben bleiben (durchgestrichen)
/// im Bestand, damit der Execution-Ring einen stabilen Nenner hat.
@MainActor
final class TodayViewModel: ObservableObject {
    /// Alle geladenen offenen Aufgaben (heute fällig + überfällig).
    @Published private(set) var tasks: [TodayTask] = []
    /// Lokal abgehakte Aufgaben-IDs (optimistisch; Rollback bei Fehler).
    @Published private(set) var doneIDs: Set<String> = []
    /// Aktiver Feuersturm-Sprint (Woche X von N), falls vorhanden.
    @Published private(set) var feuersturm: FeuersturmInfo?
    /// Heutige Termine des gewählten Timeblocking-Kalenders (für die Timeline).
    @Published private(set) var events: [CalendarEvent] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    /// True, wenn nicht geladen wird, kein Fehler vorliegt und nichts ansteht.
    var isEmpty: Bool {
        !isLoading && error == nil && tasks.isEmpty
    }

    // MARK: - Abgeleitete Sichten (für die View)

    /// Überfällige Aufgaben (Fälligkeit vor heute) — noch offen.
    var overdue: [TodayTask] {
        tasks
            .filter { !doneIDs.contains($0.id) && $0.isOverdue(referenceDate: now(), calendar: calendar) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Heute eingeplante Aufgaben für die Timeline (nach Startzeit), inkl. erledigter
    /// (durchgestrichen). Überfällige sind hier ausgenommen.
    var scheduled: [TodayTask] {
        tasks
            .filter { !$0.isOverdue(referenceDate: now(), calendar: calendar) }
            .sorted { ($0.startDate ?? $0.dueDate ?? .distantFuture) < ($1.startDate ?? $1.dueDate ?? .distantFuture) }
    }

    /// Priorität-gruppierte Sektionen offener Aufgaben (Kompatibilität/Fallback-Liste).
    var sections: [PrioritySection] {
        Self.group(
            tasks.filter { !doneIDs.contains($0.id) },
            referenceDate: now(),
            calendar: calendar
        )
    }

    /// Geplante Aufgaben gesamt (Nenner des Execution-Rings).
    var plannedCount: Int { tasks.count }
    /// Erledigte Aufgaben (Zähler).
    var doneCount: Int { doneIDs.count }
    /// Execution-Fortschritt 0…1.
    var executionProgress: Double {
        plannedCount == 0 ? 0 : Double(doneCount) / Double(plannedCount)
    }
    /// Anzahl heute geplanter Flammen (für den Feuersturm-Chip).
    var plannedFlames: Int { scheduled.filter { $0.art == .flamme }.count }

    func isDone(_ task: TodayTask) -> Bool { doneIDs.contains(task.id) }

    private let clickUp: ClickUpClienting
    private let settings: AppSettings
    private let calendarProvider: CalendarProviding
    private let calendar: Calendar
    private let now: () -> Date

    init(
        clickUp: ClickUpClienting,
        settings: AppSettings,
        calendarProvider: CalendarProviding = CalendarService(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.clickUp = clickUp
        self.settings = settings
        self.calendarProvider = calendarProvider
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Laden

    func load() async {
        guard let teamID = settings.teamID, !teamID.isEmpty else {
            tasks = []
            error = "Kein Workspace gewählt. Bitte in den Einstellungen einrichten."
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let user = try await clickUp.authorizedUser()
            let loaded = try await clickUp.todayTasks(teamID: teamID, assigneeID: user.id, now: now())
            tasks = loaded
            doneIDs = []
        } catch {
            tasks = []
            self.error = Self.message(from: error)
        }

        // Feuersturm-Überblick + Kalender additiv laden (nicht blockierend).
        await loadFeuersturm()
        events = await calendarProvider.todayEvents(now: now(), calendarID: settings.timeblockCalendarID)
    }

    private func loadFeuersturm() async {
        guard let listID = settings.phoenixListID, !listID.isEmpty else {
            feuersturm = nil
            return
        }
        feuersturm = try? await clickUp.phoenixOverview(listID: listID, now: now()).feuersturm
    }

    // MARK: - Abhaken (optimistisch, erledigt bleibt sichtbar)

    func complete(_ task: TodayTask) async {
        guard !doneIDs.contains(task.id) else { return }
        doneIDs.insert(task.id)          // optimistisch
        error = nil

        guard let listID = task.listID, !listID.isEmpty else {
            doneIDs.remove(task.id)
            error = ClickUpError.noDoneStatus(listName: task.listName).localizedDescription
            return
        }

        do {
            let statuses = try await clickUp.listStatuses(listID: listID)
            guard let done = statuses.doneStatus() else {
                doneIDs.remove(task.id)
                error = ClickUpError.noDoneStatus(listName: task.listName).localizedDescription
                return
            }
            try await clickUp.setStatus(taskID: task.id, status: done.name)
        } catch {
            doneIDs.remove(task.id)       // Rollback — Aufgabe erscheint wieder.
            self.error = Self.message(from: error)
        }
    }

    // MARK: - Timeline-Verschieben (optimistisch)

    /// Verschiebt den Start eines Fokus-Blocks; behält die Dauer (due = start + Dauer).
    func reschedule(_ task: TodayTask, to newStart: Date) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let original = tasks[index]
        let duration = TimeInterval(original.durationMinutes * 60)
        let newDue = newStart.addingTimeInterval(duration)

        tasks[index] = Self.copy(original, startDate: newStart, dueDate: newDue) // optimistisch
        error = nil

        do {
            try await clickUp.updateTaskSchedule(taskID: task.id, startDate: newStart, dueDate: newDue)
        } catch {
            if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = original } // Rollback
            self.error = Self.message(from: error)
        }
    }

    // MARK: - Helpers

    private static func copy(_ t: TodayTask, startDate: Date?, dueDate: Date?) -> TodayTask {
        TodayTask(
            id: t.id, name: t.name, priority: t.priority, dueDate: dueDate ?? t.dueDate,
            statusName: t.statusName, statusType: t.statusType, listID: t.listID,
            listName: t.listName, url: t.url, startDate: startDate ?? t.startDate,
            timeEstimateMs: t.timeEstimateMs, art: t.art
        )
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
