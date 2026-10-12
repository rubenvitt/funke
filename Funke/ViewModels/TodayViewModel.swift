import Foundation
import Combine

/// Eine Sektion der Heute-Liste: überfällig oder heute fällig.
/// (Zunder kennt keine Prioritäten – gruppiert wird nach Fälligkeit.)
struct DueSection: Identifiable, Equatable {
    enum Kind: Int, Equatable {
        case overdue
        case today
    }

    let kind: Kind
    let tasks: [TodayTask]

    var id: Int { kind.rawValue }

    var title: String {
        switch kind {
        case .overdue: return "Überfällig"
        case .today: return "Heute"
        }
    }
}

/// Lädt die heute fälligen/überfälligen Aufgaben und erlaubt das Abhaken.
/// Abhaken erfolgt optimistisch und rollt bei Fehlern sichtbar zurück.
@MainActor
final class TodayViewModel: ObservableObject {
    @Published var sections: [DueSection] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    /// True, wenn nicht geladen wird, kein Fehler vorliegt und nichts ansteht.
    var isEmpty: Bool {
        !isLoading && error == nil && sections.isEmpty
    }

    private let zunder: ZunderClienting
    private let calendar: Calendar
    private let now: () -> Date

    init(
        zunder: ZunderClienting,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.zunder = zunder
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Laden

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let reference = now()
            let tasks = try await zunder.todayTasks(now: reference)
            sections = Self.group(tasks, referenceDate: reference, calendar: calendar)
        } catch {
            sections = []
            self.error = Self.message(from: error)
        }
    }

    // MARK: - Abhaken (optimistisch)

    /// Setzt den Status in Zunder auf `done` (fester Workflow, kein Nachschlagen nötig).
    func complete(_ task: TodayTask) async {
        let snapshot = sections
        // Optimistisch entfernen.
        remove(task)
        error = nil

        do {
            try await zunder.completeTask(id: task.id, notBefore: task.updatedAt)
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
            return DueSection(kind: section.kind, tasks: remaining)
        }
    }

    /// Gruppiert in „Überfällig" (Fälligkeit vor heute) und „Heute", jeweils
    /// nach Fälligkeit sortiert (frühestes zuerst, ohne Fälligkeit zuletzt).
    static func group(
        _ tasks: [TodayTask],
        referenceDate: Date,
        calendar: Calendar
    ) -> [DueSection] {
        let sorted = tasks.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?) where l != r: return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
        let overdue = sorted.filter { $0.isOverdue(referenceDate: referenceDate, calendar: calendar) }
        let today = sorted.filter { !$0.isOverdue(referenceDate: referenceDate, calendar: calendar) }

        var sections: [DueSection] = []
        if !overdue.isEmpty { sections.append(DueSection(kind: .overdue, tasks: overdue)) }
        if !today.isEmpty { sections.append(DueSection(kind: .today, tasks: today)) }
        return sections
    }

    private static func message(from error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
