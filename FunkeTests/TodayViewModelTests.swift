import XCTest
@testable import Funke

/// Heute-Liste: Gruppierung nach Fälligkeit (statt Priorität) und optimistisches Abhaken.
@MainActor
final class TodayViewModelTests: XCTestCase {
    private var calendar: Calendar {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin") ?? TimeZone(secondsFromGMT: 7200)!
        return berlin
    }

    /// 2026-10-12 10:30 Berlin.
    private let now = Date(timeIntervalSince1970: 1_791_793_800)

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = dayOfMonth
        return calendar.date(from: parts) ?? now
    }

    func testGroupsIntoOverdueAndTodaySortedByDue() {
        let tasks = [
            TodayTask(id: "c", title: "Heute spät", status: "open", due: .dateTime(now.addingTimeInterval(3600)), locationName: "Inbox"),
            TodayTask(id: "a", title: "Vorgestern", status: "open", due: .day(day(2026, 10, 10)), locationName: "Inbox"),
            TodayTask(id: "d", title: "Heute", status: "blocked", due: .day(day(2026, 10, 12)), locationName: "Projekt"),
            TodayTask(id: "b", title: "Gestern", status: "in_progress", due: .day(day(2026, 10, 11)), locationName: "Lose"),
        ]
        let sections = TodayViewModel.group(tasks, referenceDate: now, calendar: calendar)

        XCTAssertEqual(sections.map(\.title), ["Überfällig", "Heute"])
        XCTAssertEqual(sections[0].tasks.map(\.id), ["a", "b"])
        XCTAssertEqual(sections[1].tasks.map(\.id), ["d", "c"])
    }

    func testCompleteRemovesOptimisticallyAndRollsBackOnError() async {
        let task = TodayTask(id: "t1", title: "Abhaken", status: "open", due: .day(day(2026, 10, 12)),
                             locationName: "Inbox", updatedAt: now)
        let zunder = StubZunder(tasks: [task], failComplete: true)
        let viewModel = TodayViewModel(zunder: zunder, calendar: calendar, now: { self.now })

        await viewModel.load()
        XCTAssertEqual(viewModel.sections.flatMap(\.tasks).map(\.id), ["t1"])

        await viewModel.complete(task)
        XCTAssertEqual(viewModel.sections.flatMap(\.tasks).map(\.id), ["t1"], "Rollback bei Fehler")
        XCTAssertNotNil(viewModel.error)
        let completed = await zunder.completed
        XCTAssertEqual(completed.first?.id, "t1")
        XCTAssertEqual(completed.first?.notBefore, now, "updated_at wird als HLC-Untergrenze weitergereicht")
    }

    func testCompleteSuccessKeepsTaskRemoved() async {
        let task = TodayTask(id: "t1", title: "Abhaken", status: "open", due: .day(day(2026, 10, 12)), locationName: "Inbox")
        let zunder = StubZunder(tasks: [task], failComplete: false)
        let viewModel = TodayViewModel(zunder: zunder, calendar: calendar, now: { self.now })

        await viewModel.load()
        await viewModel.complete(task)
        XCTAssertTrue(viewModel.sections.isEmpty)
        XCTAssertNil(viewModel.error)
    }
}

private actor StubZunder: ZunderClienting {
    let tasks: [TodayTask]
    let failComplete: Bool
    private(set) var completed: [(id: String, notBefore: Date?)] = []

    init(tasks: [TodayTask], failComplete: Bool) {
        self.tasks = tasks
        self.failComplete = failComplete
    }

    func currentUser() async throws -> ZunderUser { ZunderUser(name: nil, email: nil) }
    func createTask(_ draft: ZunderTaskDraft) async throws {}
    func todayTasks(now: Date) async throws -> [TodayTask] { tasks }
    func completeTask(id: String, notBefore: Date?) async throws {
        completed.append((id, notBefore))
        if failComplete { throw ZunderError.transport("offline") }
    }
}
