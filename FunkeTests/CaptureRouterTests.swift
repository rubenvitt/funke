import XCTest
@testable import Funke

/// Testet die zentrale Routing-Logik (Task vs. Notiz, Offline-Pufferung).
/// Spiegelt die plattformfreien `.verify`-Harness-Tests im echten iOS-SDK.
final class CaptureRouterTests: XCTestCase {
    private let cfg = CaptureRouterConfig(
        inboxListID: "L1", noteFolder: "Inbox",
        enrichmentEnabled: true, provider: .openRouter, openRouterModel: "m"
    )

    func testTaskClassificationCreatesClickUpTask() async throws {
        let clickUp = MockClickUp(), sink = MockNoteSink(), queue = MockQueue()
        let enr = MockEnrichment(classification: CaptureClassification(kind: .task, title: "Zahlen", body: "bis Fr", priority: .high))
        let router = CaptureRouter(clickUp: clickUp, noteSink: sink, queue: queue, enrichment: enr)

        let outcome = try await router.route(rawText: "rechnung", config: cfg)
        XCTAssertEqual(outcome, .task(queued: false))
        let created = await clickUp.created
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created.first?.name, "Zahlen")
    }

    func testNoteClassificationWritesNoteSink() async throws {
        let clickUp = MockClickUp(), sink = MockNoteSink(), queue = MockQueue()
        let enr = MockEnrichment(classification: CaptureClassification(kind: .note, title: "Idee", body: "Konzept", priority: .normal))
        let router = CaptureRouter(clickUp: clickUp, noteSink: sink, queue: queue, enrichment: enr)

        let outcome = try await router.route(rawText: "idee", config: cfg)
        XCTAssertEqual(outcome, .note(queued: false))
        let written = await sink.written
        XCTAssertEqual(written.first?.title, "Idee")
    }

    func testTransportFailureBuffersToQueue() async throws {
        let clickUp = MockClickUp(failTransport: true), sink = MockNoteSink(), queue = MockQueue()
        let enr = MockEnrichment(classification: CaptureClassification(kind: .task, title: "T", body: "", priority: .normal))
        let router = CaptureRouter(clickUp: clickUp, noteSink: sink, queue: queue, enrichment: enr)

        let outcome = try await router.route(rawText: "t", config: cfg)
        XCTAssertEqual(outcome, .task(queued: true))
        let items = await queue.items
        XCTAssertEqual(items.count, 1)
    }

    func testUnavailableAIFallsBackToNote() async throws {
        let clickUp = MockClickUp(), sink = MockNoteSink(), queue = MockQueue()
        let router = CaptureRouter(clickUp: clickUp, noteSink: sink, queue: queue, enrichment: MockEnrichment(available: false))

        let outcome = try await router.route(rawText: "Milch kaufen", config: cfg)
        XCTAssertEqual(outcome, .note(queued: false))
        let written = await sink.written
        XCTAssertEqual(written.count, 1)
    }

    func testTaskWithoutInboxListThrows() async {
        var noList = cfg; noList.inboxListID = nil
        let enr = MockEnrichment(classification: CaptureClassification(kind: .task, title: "T", body: "", priority: .normal))
        let router = CaptureRouter(clickUp: MockClickUp(), noteSink: MockNoteSink(), queue: MockQueue(), enrichment: enr)
        do {
            _ = try await router.route(rawText: "t", config: noList)
            XCTFail("Task ohne Inbox-Liste muss werfen.")
        } catch let error as ClickUpError {
            guard case .notConfigured = error else { return XCTFail("Erwartet .notConfigured, war \(error)") }
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
    }
}

// MARK: - Mocks

private actor MockClickUp: ClickUpClienting {
    var created: [(listID: String, name: String, markdown: String?, priority: Priority?)] = []
    let failTransport: Bool
    init(failTransport: Bool = false) { self.failTransport = failTransport }

    func createTask(listID: String, name: String, markdownDescription: String?, priority: Priority?) async throws {
        if failTransport { throw ClickUpError.transport("offline") }
        created.append((listID, name, markdownDescription, priority))
    }
    func authorizedUser() async throws -> ClickUpUser { fatalError("unused") }
    func teams() async throws -> [ClickUpTeam] { fatalError("unused") }
    func spaces(teamID: String) async throws -> [ClickUpSpace] { fatalError("unused") }
    func folders(spaceID: String) async throws -> [ClickUpFolder] { fatalError("unused") }
    func folderlessLists(spaceID: String) async throws -> [ClickUpList] { fatalError("unused") }
    func folderLists(folderID: String) async throws -> [ClickUpList] { fatalError("unused") }
    func todayTasks(teamID: String, assigneeID: Int, now: Date) async throws -> [TodayTask] { fatalError("unused") }
    func listStatuses(listID: String) async throws -> [ClickUpStatusInfo] { fatalError("unused") }
    func setStatus(taskID: String, status: String) async throws { fatalError("unused") }
}

private actor MockNoteSink: NoteSink {
    var written: [NoteDraft] = []
    let failTransport: Bool
    init(failTransport: Bool = false) { self.failTransport = failTransport }
    func write(_ draft: NoteDraft) async throws {
        if failTransport { throw NoteSinkError.transport("offline") }
        written.append(draft)
    }
}

private actor MockQueue: OfflineQueuing {
    var items: [PendingItem] = []
    func enqueue(_ item: PendingItem) async throws { items.append(item) }
    func all() async -> [PendingItem] { items }
    func remove(id: UUID) async throws { items.removeAll { $0.id == id } }
    func isEmpty() async -> Bool { items.isEmpty }
}

private struct MockEnrichment: EnrichmentServicing {
    var available: Bool = true
    var classification: CaptureClassification?
    func availability(for kind: EnrichmentProviderKind) async -> ProviderAvailability {
        available ? .available : .unavailable("test")
    }
    func classify(_ rawText: String, using kind: EnrichmentProviderKind, openRouterModel: String) async throws -> CaptureClassification {
        classification ?? CaptureClassification(kind: .note, title: "x", body: "y", priority: .normal)
    }
    func enrich(_ rawText: String, using kind: EnrichmentProviderKind, openRouterModel: String) async throws -> EnrichmentSuggestion { fatalError("unused") }
    func enrichNote(_ rawText: String, using kind: EnrichmentProviderKind, openRouterModel: String) async throws -> NoteSuggestion { fatalError("unused") }
}
