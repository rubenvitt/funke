import XCTest
@testable import Funke

@MainActor
final class CaptureViewModelTests: XCTestCase {

    // MARK: - Erfolg

    func testCaptureSuccessClearsTextAndFiresHaptic() async {
        let clickUp = MockClickUp()
        let settings = makeSettings(inbox: "list-1", enrichment: false)
        var haptics: [HapticFeedback] = []
        let vm = CaptureViewModel(
            clickUp: clickUp,
            enrichment: MockEnrichment(),
            settings: settings,
            queue: MockQueue(),
            transcriber: nil,
            onHaptic: { haptics.append($0) }
        )
        vm.text = "Milch kaufen"

        await vm.capture()

        XCTAssertEqual(clickUp.createdTasks.count, 1)
        XCTAssertEqual(clickUp.createdTasks.first?.listID, "list-1")
        XCTAssertEqual(clickUp.createdTasks.first?.name, "Milch kaufen")
        XCTAssertEqual(vm.text, "")
        XCTAssertEqual(vm.banner, .success("Aufgabe angelegt."))
        XCTAssertTrue(haptics.contains(.success))
    }

    // MARK: - ClickUp-Fehler (kein Transport)

    func testCaptureClickUpFailureKeepsTextAndShowsBanner() async {
        let clickUp = MockClickUp()
        clickUp.createError = ClickUpError.http(status: 401, message: "Token ungültig")
        let settings = makeSettings(inbox: "list-1", enrichment: false)
        let vm = CaptureViewModel(
            clickUp: clickUp,
            enrichment: MockEnrichment(),
            settings: settings,
            queue: MockQueue(),
            transcriber: nil
        )
        vm.text = "Wichtige Aufgabe"

        await vm.capture()

        XCTAssertEqual(vm.text, "Wichtige Aufgabe", "Text muss bei Fehler erhalten bleiben")
        if case .failure = vm.banner {} else {
            XCTFail("Erwartete Fehler-Banner, war: \(String(describing: vm.banner))")
        }
        XCTAssertTrue(clickUp.createdTasks.isEmpty)
    }

    // MARK: - Offline (Transport-Fehler → Queue)

    func testCaptureTransportFailureEnqueues() async {
        let clickUp = MockClickUp()
        clickUp.createError = ClickUpError.transport("Keine Verbindung")
        let queue = MockQueue()
        let settings = makeSettings(inbox: "list-1", enrichment: false)
        let vm = CaptureViewModel(
            clickUp: clickUp,
            enrichment: MockEnrichment(),
            settings: settings,
            queue: queue,
            transcriber: nil
        )
        vm.text = "Offline-Aufgabe"

        await vm.capture()

        let pending = await queue.all()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.name, "Offline-Aufgabe")
        XCTAssertEqual(vm.text, "")
        XCTAssertEqual(vm.pendingCount, 1)
        if case .success = vm.banner {} else {
            XCTFail("Erwartete Erfolgs-Banner (offline gepuffert)")
        }
    }

    // MARK: - KI-an-Pfad (enrich → review)

    func testCaptureWithEnrichmentSetsReview() async {
        let clickUp = MockClickUp()
        let enrichment = MockEnrichment()
        enrichment.result = EnrichmentSuggestion(title: "Veredelt", details: "Mehr", priority: .high)
        let settings = makeSettings(inbox: "list-1", enrichment: true)
        let vm = CaptureViewModel(
            clickUp: clickUp,
            enrichment: enrichment,
            settings: settings,
            queue: MockQueue(),
            transcriber: nil
        )
        vm.text = "roh"

        await vm.capture()

        XCTAssertEqual(vm.review?.title, "Veredelt")
        XCTAssertEqual(vm.review?.priority, .high)
        XCTAssertTrue(clickUp.createdTasks.isEmpty, "Anlegen erst nach confirm()")
        XCTAssertEqual(vm.text, "roh", "Text bleibt bis confirm() stehen")
    }

    func testConfirmCreatesTaskFromEditedSuggestion() async {
        let clickUp = MockClickUp()
        let settings = makeSettings(inbox: "list-1", enrichment: true)
        let vm = CaptureViewModel(
            clickUp: clickUp,
            enrichment: MockEnrichment(),
            settings: settings,
            queue: MockQueue(),
            transcriber: nil
        )
        let edited = EnrichmentSuggestion(title: "Final", details: "Details", priority: .urgent)

        await vm.confirm(edited)

        XCTAssertEqual(clickUp.createdTasks.count, 1)
        XCTAssertEqual(clickUp.createdTasks.first?.name, "Final")
        XCTAssertEqual(clickUp.createdTasks.first?.markdownDescription, "Details")
        XCTAssertEqual(clickUp.createdTasks.first?.priority, .urgent)
        XCTAssertNil(vm.review)
    }

    // MARK: - KI-Fehler (Banner, kein Crash, Roh-Capture weiter möglich)

    func testEnrichmentErrorShowsBannerKeepsTextNoReview() async {
        let clickUp = MockClickUp()
        let enrichment = MockEnrichment()
        enrichment.error = EnrichmentError.transport("KI weg")
        let settings = makeSettings(inbox: "list-1", enrichment: true)
        let vm = CaptureViewModel(
            clickUp: clickUp,
            enrichment: enrichment,
            settings: settings,
            queue: MockQueue(),
            transcriber: nil
        )
        vm.text = "Notiz"

        await vm.capture()

        if case .failure = vm.banner {} else {
            XCTFail("Erwartete Fehler-Banner bei KI-Fehler")
        }
        XCTAssertNil(vm.review)
        XCTAssertEqual(vm.text, "Notiz", "Roh-Text bleibt für Fallback erhalten")
        XCTAssertTrue(clickUp.createdTasks.isEmpty)

        // Roh-Capture muss weiterhin möglich sein: KI aus, erneut erfassen.
        settings.enrichmentEnabled = false
        await vm.capture()
        XCTAssertEqual(clickUp.createdTasks.count, 1, "Roh-Anlegen nach KI-Fehler möglich")
        XCTAssertEqual(vm.text, "")
    }

    func testEnrichmentUnavailableFallsBackToRawCreate() async {
        let clickUp = MockClickUp()
        let enrichment = MockEnrichment()
        enrichment.available = .unavailable("Kein Schlüssel")
        let settings = makeSettings(inbox: "list-1", enrichment: true)
        let vm = CaptureViewModel(
            clickUp: clickUp,
            enrichment: enrichment,
            settings: settings,
            queue: MockQueue(),
            transcriber: nil
        )
        vm.text = "ohne KI"

        await vm.capture()

        XCTAssertNil(vm.review)
        XCTAssertEqual(clickUp.createdTasks.count, 1, "Bei nicht verfügbarer KI roh anlegen")
        XCTAssertEqual(vm.text, "")
    }

    // MARK: - Inbox nicht konfiguriert

    func testMissingInboxShowsBannerNoCreate() async {
        let clickUp = MockClickUp()
        let settings = makeSettings(inbox: nil, enrichment: false)
        let vm = CaptureViewModel(
            clickUp: clickUp,
            enrichment: MockEnrichment(),
            settings: settings,
            queue: MockQueue(),
            transcriber: nil
        )
        vm.text = "irgendwas"

        await vm.capture()

        if case .failure = vm.banner {} else {
            XCTFail("Erwartete Fehler-Banner bei fehlender Inbox")
        }
        XCTAssertTrue(clickUp.createdTasks.isEmpty)
        XCTAssertEqual(vm.text, "irgendwas")
    }

    // MARK: - Leerer Text

    func testEmptyTextIsIgnored() async {
        let clickUp = MockClickUp()
        let settings = makeSettings(inbox: "list-1", enrichment: false)
        let vm = CaptureViewModel(
            clickUp: clickUp,
            enrichment: MockEnrichment(),
            settings: settings,
            queue: MockQueue(),
            transcriber: nil
        )
        vm.text = "   "

        await vm.capture()

        XCTAssertTrue(clickUp.createdTasks.isEmpty)
        XCTAssertNil(vm.banner)
    }

    // MARK: - Sprachaufnahme

    func testToggleRecordingStartsAndStreamsPartialIntoText() async {
        let transcriber = MockTranscriber()
        transcriber.partialToEmit = "diktierter Text"
        let settings = makeSettings(inbox: "list-1", enrichment: false)
        let vm = CaptureViewModel(
            clickUp: MockClickUp(),
            enrichment: MockEnrichment(),
            settings: settings,
            queue: MockQueue(),
            transcriber: transcriber
        )

        await vm.toggleRecording()

        XCTAssertTrue(transcriber.didStart)
        XCTAssertTrue(vm.isRecording)
        // Partielles Ergebnis wird über ein inneres Task auf den MainActor gehoppt;
        // kurz pollen, statt auf eine einzelne Yield-Reihenfolge zu vertrauen.
        for _ in 0..<50 where vm.text.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(vm.text, "diktierter Text")

        await vm.toggleRecording()
        XCTAssertTrue(transcriber.didStop)
        XCTAssertFalse(vm.isRecording)
    }

    func testToggleRecordingWithoutTranscriberShowsBanner() async {
        let settings = makeSettings(inbox: "list-1", enrichment: false)
        let vm = CaptureViewModel(
            clickUp: MockClickUp(),
            enrichment: MockEnrichment(),
            settings: settings,
            queue: MockQueue(),
            transcriber: nil
        )

        await vm.toggleRecording()

        XCTAssertFalse(vm.isRecording)
        if case .failure = vm.banner {} else {
            XCTFail("Erwartete Fehler-Banner ohne Transkriber")
        }
    }

    // MARK: - flushQueue

    func testFlushQueueSendsAndRemoves() async {
        let clickUp = MockClickUp()
        let queue = MockQueue()
        try? await queue.enqueue(PendingCapture(name: "A"))
        try? await queue.enqueue(PendingCapture(name: "B"))
        let settings = makeSettings(inbox: "list-1", enrichment: false)
        let vm = CaptureViewModel(
            clickUp: clickUp,
            enrichment: MockEnrichment(),
            settings: settings,
            queue: queue,
            transcriber: nil
        )

        await vm.flushQueue()

        XCTAssertEqual(clickUp.createdTasks.count, 2)
        let remaining = await queue.all()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(vm.pendingCount, 0)
    }

    // MARK: - Helpers

    private func makeSettings(inbox: String?, enrichment: Bool) -> AppSettings {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.inboxListID = inbox
        settings.enrichmentEnabled = enrichment
        return settings
    }
}

// MARK: - Mocks

private final class MockClickUp: ClickUpClienting, @unchecked Sendable {
    struct CreatedTask: Equatable {
        let listID: String
        let name: String
        let markdownDescription: String?
        let priority: Priority?
    }

    var createdTasks: [CreatedTask] = []
    var createError: Error?
    var statuses: [ClickUpStatusInfo] = []
    var setStatusCalls: [(taskID: String, status: String)] = []
    var todayTasksResult: [TodayTask] = []
    var user = ClickUpUser(id: 42, username: "tester")

    func authorizedUser() async throws -> ClickUpUser { user }
    func teams() async throws -> [ClickUpTeam] { [] }
    func spaces(teamID: String) async throws -> [ClickUpSpace] { [] }
    func folders(spaceID: String) async throws -> [ClickUpFolder] { [] }
    func folderlessLists(spaceID: String) async throws -> [ClickUpList] { [] }
    func folderLists(folderID: String) async throws -> [ClickUpList] { [] }

    func createTask(
        listID: String,
        name: String,
        markdownDescription: String?,
        priority: Priority?
    ) async throws {
        if let createError { throw createError }
        createdTasks.append(
            CreatedTask(
                listID: listID,
                name: name,
                markdownDescription: markdownDescription,
                priority: priority
            )
        )
    }

    func todayTasks(teamID: String, assigneeID: Int, now: Date) async throws -> [TodayTask] {
        todayTasksResult
    }

    func listStatuses(listID: String) async throws -> [ClickUpStatusInfo] { statuses }

    func setStatus(taskID: String, status: String) async throws {
        setStatusCalls.append((taskID, status))
    }
}

private final class MockEnrichment: EnrichmentServicing, @unchecked Sendable {
    var available: ProviderAvailability = .available
    var result: EnrichmentSuggestion = EnrichmentSuggestion(title: "Vorschlag")
    var error: Error?

    func availability(for kind: EnrichmentProviderKind) async -> ProviderAvailability {
        available
    }

    func enrich(
        _ rawText: String,
        using kind: EnrichmentProviderKind,
        openRouterModel: String
    ) async throws -> EnrichmentSuggestion {
        if let error { throw error }
        return result
    }

    func enrichNote(
        _ rawText: String,
        using kind: EnrichmentProviderKind,
        openRouterModel: String
    ) async throws -> NoteSuggestion {
        if let error { throw error }
        return NoteSuggestion(title: result.title, body: result.details ?? result.title)
    }
}

private actor MockQueue: OfflineQueuing {
    private var items: [PendingCapture] = []

    func enqueue(_ capture: PendingCapture) async throws { items.append(capture) }
    func all() async -> [PendingCapture] { items }
    func remove(id: UUID) async throws { items.removeAll { $0.id == id } }
    func isEmpty() async -> Bool { items.isEmpty }
}

@MainActor
private final class MockTranscriber: SpeechTranscribing {
    var isAvailable: Bool = true
    var authorized: Bool = true
    var didStart = false
    var didStop = false
    var startError: Error?
    var partialToEmit: String?

    func requestAuthorization() async -> Bool { authorized }

    func start(onPartialResult: @escaping (String) -> Void) throws {
        if let startError { throw startError }
        didStart = true
        if let partialToEmit { onPartialResult(partialToEmit) }
    }

    func stop() { didStop = true }
}
