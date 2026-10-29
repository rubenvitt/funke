import XCTest
@testable import Funke

/// Tests für den Weg der Aufgaben übers Vault Cockpit (VCP-119): Request-Bau,
/// Rückfall an Zunder und Fehler-Mapping für die Offline-Queue.
final class CockpitTaskClientTests: XCTestCase {

    private static let relayURL = URL(string: "https://vault.example/funke")!
    private static let draft = ZunderTaskDraft(
        taskID: "01a1f805-eba0-77ee-a761-5ef35f30e49b",
        ops: [
            ZunderOp(opID: "o1", entity: "task", entityID: "01a1f805-eba0-77ee-a761-5ef35f30e49b",
                     field: "title", value: .string("Zahnarzt anrufen morgen."), hlc: "h1"),
            ZunderOp(opID: "o2", entity: "task", entityID: "01a1f805-eba0-77ee-a761-5ef35f30e49b",
                     field: "location", value: .object(["kind": .string("inbox")]), hlc: "h2"),
            ZunderOp(opID: "o3", entity: "task", entityID: "01a1f805-eba0-77ee-a761-5ef35f30e49b",
                     field: "description", value: .string("Wegen Kontrolle"), hlc: "h3"),
        ]
    )

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = StubURLProtocol.makeSession()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    private func makeClient(inner: RecordingZunder, relay: Bool = true) -> CockpitTaskClient {
        CockpitTaskClient(
            inner: inner,
            relay: { relay ? (baseURL: Self.relayURL, token: "vct_test") : nil },
            session: session
        )
    }

    func testSendsTaskToCockpit() async throws {
        let inner = RecordingZunder()
        StubURLProtocol.enqueue(statusCode: 201, json: #"{"ok":true,"kind":"task"}"#)

        try await makeClient(inner: inner).createTask(Self.draft)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://vault.example/funke/tasks")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer vct_test")
        let body = try XCTUnwrap(StubURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, [
            "id": "01a1f805-eba0-77ee-a761-5ef35f30e49b",
            "title": "Zahnarzt anrufen morgen.",
            "description": "Wegen Kontrolle",
        ])
        let created = await inner.created
        XCTAssertTrue(created.isEmpty, "Zunder direkt darf nicht zusätzlich angelegt werden.")
    }

    func testRepeatedSendIsAccepted() async throws {
        let inner = RecordingZunder()
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"ok":true,"duplicate":true}"#)
        try await makeClient(inner: inner).createTask(Self.draft)
        let created = await inner.created
        XCTAssertTrue(created.isEmpty)
    }

    func testWithoutRelayGoesDirectlyToZunder() async throws {
        let inner = RecordingZunder()
        try await makeClient(inner: inner, relay: false).createTask(Self.draft)
        XCTAssertNil(StubURLProtocol.lastRequest)
        let created = await inner.created
        XCTAssertEqual(created, [Self.draft])
    }

    func testFallsBackWhenCockpitCannotTakeTasks() async throws {
        for status in [404, 405, 503] {
            StubURLProtocol.reset()
            let inner = RecordingZunder()
            StubURLProtocol.enqueue(statusCode: status, json: #"{"error":"x"}"#)
            try await makeClient(inner: inner).createTask(Self.draft)
            let created = await inner.created
            XCTAssertEqual(created, [Self.draft], "HTTP \(status) → direkt an Zunder")
        }
    }

    func testTransportErrorIsRetryableAndDoesNotFallBack() async {
        let inner = RecordingZunder()
        StubURLProtocol.enqueue(error: URLError(.notConnectedToInternet))
        do {
            try await makeClient(inner: inner).createTask(Self.draft)
            XCTFail("Erwartete ZunderError.transport")
        } catch let error as ZunderError {
            XCTAssertTrue(error.isRetryable)
        } catch {
            XCTFail("Unerwarteter Fehler: \(error)")
        }
        let created = await inner.created
        XCTAssertTrue(created.isEmpty, "Kein Rückfall: das Nachsenden ans Cockpit ist idempotent.")
    }

    func testRejectionCarriesCockpitMessage() async {
        let inner = RecordingZunder()
        StubURLProtocol.enqueue(statusCode: 502, json: #"{"error":"Titel zu lang","status":502,"message":"Zunder lehnt ab: Titel zu lang"}"#)
        do {
            try await makeClient(inner: inner).createTask(Self.draft)
            XCTFail("Erwartete ZunderError.rejected")
        } catch let error as ZunderError {
            XCTAssertEqual(error, .rejected("Zunder lehnt ab: Titel zu lang"))
        } catch {
            XCTFail("Unerwarteter Fehler: \(error)")
        }
    }

    func testServerErrorIsRetryable() async {
        let inner = RecordingZunder()
        StubURLProtocol.enqueue(statusCode: 500, json: #"{"error":"kaputt"}"#)
        do {
            try await makeClient(inner: inner).createTask(Self.draft)
            XCTFail("Erwartete ZunderError.http")
        } catch let error as ZunderError {
            XCTAssertTrue(error.isRetryable)
        } catch {
            XCTFail("Unerwarteter Fehler: \(error)")
        }
    }
}

private actor RecordingZunder: ZunderClienting {
    private(set) var created: [ZunderTaskDraft] = []

    func createTask(_ draft: ZunderTaskDraft) async throws { created.append(draft) }
    func currentUser() async throws -> ZunderUser { ZunderUser(name: "Test", email: nil) }
    func todayTasks(now: Date) async throws -> [TodayTask] { [] }
    func completeTask(id: String, notBefore: Date?) async throws {}
}
