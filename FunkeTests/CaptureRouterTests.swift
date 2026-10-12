import XCTest
@testable import Funke

/// Testet die zentrale Routing-Logik (Task vs. Notiz, Offline-Pufferung,
/// idempotentes Nachsenden an Zunder).
final class CaptureRouterTests: XCTestCase {
    private let cfg = CaptureRouterConfig(
        noteFolder: "Inbox",
        enrichmentEnabled: true, provider: .openRouter, openRouterModel: "m"
    )
    private let drafts = ZunderOpFactory(node: "funke-0a1b2c3d", clock: HybridLogicalClock())

    private func makeRouter(
        zunder: ZunderClienting,
        sink: NoteSink = MockNoteSink(),
        queue: OfflineQueuing,
        enrichment: EnrichmentServicing = MockEnrichment()
    ) -> CaptureRouter {
        CaptureRouter(zunder: zunder, drafts: drafts, noteSink: sink, queue: queue, enrichment: enrichment)
    }

    func testTaskClassificationCreatesZunderTask() async throws {
        let zunder = MockZunder(), queue = MockQueue()
        let enr = MockEnrichment(classification: CaptureClassification(kind: .task, title: "Zahlen", body: "bis Fr"))
        let router = makeRouter(zunder: zunder, queue: queue, enrichment: enr)

        let outcome = try await router.route(rawText: "rechnung", config: cfg)
        XCTAssertEqual(outcome, .task(queued: false))
        let created = await zunder.created
        XCTAssertEqual(created.count, 1)
        let draft = try XCTUnwrap(created.first)
        XCTAssertEqual(draft.ops.first { $0.field == "title" }?.value, .string("Zahlen"))
        XCTAssertEqual(draft.ops.first { $0.field == "description" }?.value, .string("bis Fr"))
        XCTAssertEqual(draft.ops.first { $0.field == "location" }?.value, .object(["kind": .string("inbox")]))
        XCTAssertNil(draft.ops.first { $0.field == "priority" })
    }

    func testNoteClassificationWritesNoteSink() async throws {
        let sink = MockNoteSink()
        let enr = MockEnrichment(classification: CaptureClassification(kind: .note, title: "Idee", body: "Konzept"))
        let router = makeRouter(zunder: MockZunder(), sink: sink, queue: MockQueue(), enrichment: enr)

        let outcome = try await router.route(rawText: "idee", config: cfg)
        XCTAssertEqual(outcome, .note(queued: false))
        let written = await sink.written
        XCTAssertEqual(written.first?.title, "Idee")
    }

    func testTransportFailureBuffersTheAttemptedDraft() async throws {
        let zunder = MockZunder(mode: .transport), queue = MockQueue()
        let enr = MockEnrichment(classification: CaptureClassification(kind: .task, title: "T", body: ""))
        let router = makeRouter(zunder: zunder, queue: queue, enrichment: enr)

        let outcome = try await router.route(rawText: "t", config: cfg)
        XCTAssertEqual(outcome, .task(queued: true))
        let items = await queue.items
        XCTAssertEqual(items.count, 1)
        guard case .task(let pending) = items.first else { return XCTFail("Task erwartet") }
        let attempted = await zunder.attempted
        XCTAssertEqual(pending.draft, attempted.first, "Gepuffert wird exakt der versuchte Entwurf")
        XCTAssertEqual(pending.title, "T")
        XCTAssertNil(pending.description)
    }

    func testRejectedTaskThrowsAndIsNotQueued() async {
        let zunder = MockZunder(mode: .rejected("Titel ist zu lang")), queue = MockQueue()
        let enr = MockEnrichment(classification: CaptureClassification(kind: .task, title: "T", body: ""))
        let router = makeRouter(zunder: zunder, queue: queue, enrichment: enr)
        do {
            _ = try await router.route(rawText: "t", config: cfg)
            XCTFail("Ablehnung muss geworfen werden.")
        } catch let error as ZunderError {
            XCTAssertEqual(error, .rejected("Titel ist zu lang"))
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
        let items = await queue.items
        XCTAssertTrue(items.isEmpty, "Abgelehntes darf nicht gepuffert werden")
    }

    func testUnavailableAIFallsBackToNote() async throws {
        let sink = MockNoteSink()
        let router = makeRouter(zunder: MockZunder(), sink: sink, queue: MockQueue(), enrichment: MockEnrichment(available: false))

        let outcome = try await router.route(rawText: "Milch kaufen", config: cfg)
        XCTAssertEqual(outcome, .note(queued: false))
        let written = await sink.written
        XCTAssertEqual(written.count, 1)
    }

    func testTaskWithoutZunderTokenThrowsAndIsNotQueued() async {
        let client = ZunderClient(
            secrets: EmptySecrets(), baseURL: { "https://zunder.example" }, factory: drafts
        )
        let queue = MockQueue()
        let enr = MockEnrichment(classification: CaptureClassification(kind: .task, title: "T", body: ""))
        let router = makeRouter(zunder: client, queue: queue, enrichment: enr)
        do {
            _ = try await router.route(rawText: "t", config: cfg)
            XCTFail("Task ohne Token muss werfen.")
        } catch let error as ZunderError {
            XCTAssertEqual(error, .missingToken)
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
        let items = await queue.items
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Nachsenden

    func testFlushReplaysPersistedDraftUnchanged() async throws {
        let zunder = MockZunder(), queue = MockQueue()
        let draft = drafts.makeTaskDraft(title: "Gepuffert", description: "Text")
        try await queue.enqueue(.task(PendingCapture(title: "Gepuffert", description: "Text", draft: draft)))
        let router = makeRouter(zunder: zunder, queue: queue)

        let result = await router.flushQueue(config: cfg)
        XCTAssertEqual(result.remaining, 0)
        XCTAssertNil(result.failure)
        let created = await zunder.created
        XCTAssertEqual(created, [draft], "Nachsenden nutzt exakt die gespeicherten op_ids/HLCs")
    }

    func testFlushUpgradesLegacyClickUpItemAndPersistsDraftBeforeSending() async throws {
        // Ein Queue-Eintrag aus der ClickUp-Zeit (name/markdownDescription/priority).
        let legacyJSON = """
        {"kind":"task","task":{"id":"\(UUID().uuidString)","name":"Alt-Task",
         "markdownDescription":"**alt**","priority":2,"createdAt":"2026-06-15T14:30:00Z"}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(PendingItem.self, from: Data(legacyJSON.utf8))
        guard case .task(let legacyTask) = legacy else { return XCTFail("Task erwartet") }
        XCTAssertEqual(legacyTask.title, "Alt-Task")
        XCTAssertEqual(legacyTask.description, "**alt**")
        XCTAssertNil(legacyTask.draft)

        let zunder = MockZunder(mode: .transport), queue = MockQueue()
        try await queue.enqueue(legacy)
        let router = makeRouter(zunder: zunder, queue: queue)

        // 1. Flush: offline → Eintrag bleibt, hat aber jetzt einen persistierten Entwurf.
        let first = await router.flushQueue(config: cfg)
        XCTAssertEqual(first.remaining, 1)
        XCTAssertNotNil(first.failure)
        let afterFirst = await queue.items
        guard case .task(let upgraded) = afterFirst.first else { return XCTFail("Task erwartet") }
        let persisted = try XCTUnwrap(upgraded.draft, "Entwurf muss vor dem Senden persistiert sein")
        XCTAssertEqual(upgraded.id, legacyTask.id)
        let attempted = await zunder.attempted
        XCTAssertEqual(attempted, [persisted])

        // 2. Flush: online → derselbe Entwurf wird gesendet (keine Duplikate).
        await zunder.setMode(.ok)
        let second = await router.flushQueue(config: cfg)
        XCTAssertEqual(second.remaining, 0)
        let created = await zunder.created
        XCTAssertEqual(created, [persisted])
        XCTAssertEqual(persisted.ops.first { $0.field == "title" }?.value, .string("Alt-Task"))
        XCTAssertEqual(persisted.ops.first { $0.field == "description" }?.value, .string("**alt**"))
    }

    func testFlushTurnsRejectedTaskIntoBufferedNote() async throws {
        let zunder = MockZunder(mode: .rejected("Ungültig")), queue = MockQueue()
        let draft = drafts.makeTaskDraft(title: "Kaputt", description: "Inhalt")
        try await queue.enqueue(.task(PendingCapture(title: "Kaputt", description: "Inhalt", draft: draft)))
        let router = makeRouter(zunder: zunder, queue: queue)

        let result = await router.flushQueue(config: cfg)
        XCTAssertEqual(result.remaining, 1, "Inhalt bleibt als Notiz erhalten")
        XCTAssertTrue(result.failure?.contains("Ungültig") ?? false)
        let items = await queue.items
        guard case .note(let note) = items.first else { return XCTFail("Notiz erwartet") }
        XCTAssertEqual(note.title, "Kaputt")
        XCTAssertEqual(note.body, "Kaputt\n\nInhalt")
        XCTAssertEqual(note.folder, "Inbox")
    }
}

// MARK: - Mocks

private actor MockZunder: ZunderClienting {
    enum Mode: Sendable {
        case ok
        case transport
        case rejected(String)
    }

    private(set) var created: [ZunderTaskDraft] = []
    private(set) var attempted: [ZunderTaskDraft] = []
    private var mode: Mode

    init(mode: Mode = .ok) { self.mode = mode }

    func setMode(_ mode: Mode) { self.mode = mode }

    func createTask(_ draft: ZunderTaskDraft) async throws {
        attempted.append(draft)
        switch mode {
        case .ok: created.append(draft)
        case .transport: throw ZunderError.transport("offline")
        case .rejected(let message): throw ZunderError.rejected(message)
        }
    }
    func currentUser() async throws -> ZunderUser { ZunderUser(name: "Test", email: nil) }
    func todayTasks(now: Date) async throws -> [TodayTask] { [] }
    func completeTask(id: String, notBefore: Date?) async throws {}
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
    func update(_ item: PendingItem) async throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }
    func isEmpty() async -> Bool { items.isEmpty }
}

private struct MockEnrichment: EnrichmentServicing {
    var available: Bool = true
    var classification: CaptureClassification?
    func availability(for kind: EnrichmentProviderKind) async -> ProviderAvailability {
        available ? .available : .unavailable("test")
    }
    func classify(_ rawText: String, using kind: EnrichmentProviderKind, openRouterModel: String) async throws -> CaptureClassification {
        classification ?? CaptureClassification(kind: .note, title: "x", body: "y")
    }
    func enrich(_ rawText: String, using kind: EnrichmentProviderKind, openRouterModel: String) async throws -> EnrichmentSuggestion { fatalError("unused") }
    func enrichNote(_ rawText: String, using kind: EnrichmentProviderKind, openRouterModel: String) async throws -> NoteSuggestion { fatalError("unused") }
}

private struct EmptySecrets: SecretStoring {
    func string(for key: SecretKey) -> String? { nil }
    func setString(_ value: String?, for key: SecretKey) throws {}
}
