import XCTest
@testable import Funke

/// Tests für den Zunder-Client (Request-Bau, Push-Format, Idempotenz,
/// Fehler-Mapping, MCP-Heute-Liste) und die Op-Fabrik (UUIDv7, HLC).
final class ZunderClientTests: XCTestCase {

    private static let token = "zt_testtoken_ABCDEF"
    private static let node = "funke-0a1b2c3d"
    private static let base = "https://zunder.example/"
    /// 2026-10-12 08:30:00 UTC (= 10:30 in Berlin).
    private static let fixedNow = Date(timeIntervalSince1970: 1_791_793_800)

    private static let uuidPattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    private static let uuidV7Pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
    private static let hlcPattern = "^[0-9]{13}:[0-9]{5}:funke-0a1b2c3d$"

    private var session: URLSession!
    private var calendar: Calendar!
    private var factory: ZunderOpFactory!
    private var client: ZunderClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = StubURLProtocol.makeSession()
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin") ?? TimeZone(secondsFromGMT: 7200)!
        calendar = berlin
        factory = Self.makeFactory()
        client = makeClient(secrets: MockSecretStore(values: [.zunderToken: Self.token]))
    }

    override func tearDown() {
        StubURLProtocol.reset()
        session = nil
        calendar = nil
        factory = nil
        client = nil
        super.tearDown()
    }

    // MARK: - Konfiguration / Token

    func testMissingTokenThrows() async {
        let noToken = makeClient(secrets: MockSecretStore(values: [:]))
        await assertThrows(ZunderError.missingToken) {
            _ = try await noToken.currentUser()
        }
        XCTAssertNil(StubURLProtocol.lastRequest, "Ohne Token darf nichts gesendet werden.")
    }

    func testMissingBaseURLThrowsNotConfigured() async {
        let noURL = makeClient(secrets: MockSecretStore(values: [.zunderToken: Self.token]), base: "  ")
        do {
            _ = try await noURL.currentUser()
            XCTFail("Erwartete ZunderError.notConfigured")
        } catch let error as ZunderError {
            guard case .notConfigured = error else { return XCTFail("Erwartet .notConfigured, war \(error)") }
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
    }

    func testInvalidBaseURLThrows() async {
        let ftp = makeClient(secrets: MockSecretStore(values: [.zunderToken: Self.token]), base: "ftp://zunder.example")
        await assertThrows(ZunderError.invalidURL) {
            _ = try await ftp.currentUser()
        }
    }

    // MARK: - /api/me

    func testCurrentUserRequestAndParsing() async throws {
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"user_id":1,"name":"Ruben","email":"ruben@example.org"}"#)
        let user = try await client.currentUser()

        XCTAssertEqual(user, ZunderUser(name: "Ruben", email: "ruben@example.org"))
        XCTAssertEqual(user.displayName, "Ruben (ruben@example.org)")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://zunder.example/api/me")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(Self.token)")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Zunder-Client"), "Bearer braucht keinen CSRF-Header")
    }

    func testCurrentUserToleratesNullNameAndEmail() async throws {
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"user_id":1,"name":null,"email":null}"#)
        let user = try await client.currentUser()
        XCTAssertEqual(user.displayName, "Zunder-Besitzer")
    }

    // MARK: - Push: Body-Form

    func testCreateTaskPushBodyShape() async throws {
        let draft = factory.makeTaskDraft(title: "Zahnarzt anrufen", description: "**bis Freitag**")
        StubURLProtocol.enqueue(statusCode: 200, json: acceptAll(draft.ops))

        try await client.createTask(draft)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://zunder.example/api/sync/push")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(Self.token)")

        let body = try lastBodyJSON()
        XCTAssertEqual(body["client_id"] as? String, Self.node)
        let ops = try XCTUnwrap(body["ops"] as? [[String: Any]])
        XCTAssertEqual(ops.count, 3)

        var fields: [String: Any] = [:]
        var opIDs = Set<String>()
        for op in ops {
            XCTAssertEqual(Set(op.keys), ["op_id", "entity", "entity_id", "field", "value", "hlc"])
            XCTAssertEqual(op["entity"] as? String, "task")
            XCTAssertEqual(op["entity_id"] as? String, draft.taskID)
            let opID = try XCTUnwrap(op["op_id"] as? String)
            XCTAssertTrue(matches(opID, Self.uuidPattern), "op_id nicht kanonisch: \(opID)")
            opIDs.insert(opID)
            let hlc = try XCTUnwrap(op["hlc"] as? String)
            XCTAssertTrue(matches(hlc, Self.hlcPattern), "HLC-Format falsch: \(hlc)")
            let field = try XCTUnwrap(op["field"] as? String)
            fields[field] = op["value"]
        }
        XCTAssertEqual(opIDs.count, 3, "op_ids müssen eindeutig sein")
        XCTAssertTrue(matches(draft.taskID, Self.uuidV7Pattern), "Aufgaben-ID soll UUIDv7 sein: \(draft.taskID)")
        XCTAssertEqual(fields["title"] as? String, "Zahnarzt anrufen")
        XCTAssertEqual(fields["description"] as? String, "**bis Freitag**")
        let location = try XCTUnwrap(fields["location"] as? [String: Any])
        XCTAssertEqual(location as? [String: String], ["kind": "inbox"])
        XCTAssertNil(fields["priority"], "Zunder kennt keine Priorität")
    }

    func testDraftWithoutDescriptionOmitsDescriptionOp() {
        let draft = factory.makeTaskDraft(title: "Nur Titel", description: "   ")
        XCTAssertEqual(draft.ops.map(\.field), ["title", "location"])
    }

    func testOverlongTitleIsShortenedAndKeptInDescription() throws {
        let long = String(repeating: "a", count: 600)
        let draft = factory.makeTaskDraft(title: long, description: nil)
        let title = try XCTUnwrap(draft.ops.first { $0.field == "title" }?.value)
        guard case .string(let shortened) = title else { return XCTFail("title kein String") }
        XCTAssertEqual(shortened.count, ZunderOpFactory.maxTitleLength)
        XCTAssertEqual(draft.ops.first { $0.field == "description" }?.value, .string(long))
    }

    // MARK: - Idempotenz

    func testReplayAfterTimeoutSendsByteIdenticalOps() async throws {
        let draft = factory.makeTaskDraft(title: "Steuer", description: "Belege sammeln")

        // 1. Versuch: Timeout → retrybarer Transportfehler.
        StubURLProtocol.enqueue(error: URLError(.timedOut))
        do {
            try await client.createTask(draft)
            XCTFail("Erwartete Transportfehler")
        } catch let error as ZunderError {
            guard case .transport = error else { return XCTFail("Erwartet .transport, war \(error)") }
            XCTAssertTrue(error.isRetryable)
        }

        // Puffern wie die OfflineQueue (JSON mit ISO-Datum, sortiert) und zurücklesen.
        let pending = PendingCapture(title: "Steuer", description: "Belege sammeln", draft: draft)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(PendingCapture.self, from: encoder.encode(pending))
        let restoredDraft = try XCTUnwrap(restored.draft)
        XCTAssertEqual(restoredDraft, draft)

        // 2. Versuch mit dem gepufferten Entwurf.
        StubURLProtocol.enqueue(statusCode: 200, json: acceptAll(draft.ops))
        try await client.createTask(restoredDraft)

        XCTAssertEqual(StubURLProtocol.requestBodies.count, 2)
        let first = try XCTUnwrap(StubURLProtocol.requestBodies[0])
        let second = try XCTUnwrap(StubURLProtocol.requestBodies[1])
        XCTAssertEqual(first, second, "Nachsenden muss byte-identisch sein (gleiche op_ids/HLCs)")
    }

    // MARK: - Ablehnung / Fehler

    func testRejectedOpsThrowRejectedWithServerMessage() async {
        let draft = factory.makeTaskDraft(title: "x", description: nil)
        let json = """
        {"accepted":[],"rejected":[
          {"op_id":"\(draft.ops[1].opID)","code":"entity_rejected","message":"Andere Operation dieser Aufgabe war ungültig"},
          {"op_id":"\(draft.ops[0].opID)","code":"invalid_value","message":"Titel ist zu lang"}
        ],"warnings":[],"cursor":7}
        """
        StubURLProtocol.enqueue(statusCode: 200, json: json)
        do {
            try await client.createTask(draft)
            XCTFail("Erwartete ZunderError.rejected")
        } catch let error as ZunderError {
            XCTAssertEqual(error, .rejected("Titel ist zu lang"))
            XCTAssertFalse(error.isRetryable, "Ablehnung darf nicht gepuffert werden")
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
    }

    func testUnacknowledgedOpsThrowDecoding() async {
        let draft = factory.makeTaskDraft(title: "x", description: nil)
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"accepted":["\#(draft.ops[0].opID)"],"rejected":[],"warnings":[],"cursor":3}"#)
        do {
            try await client.createTask(draft)
            XCTFail("Erwartete ZunderError.decoding")
        } catch let error as ZunderError {
            guard case .decoding = error else { return XCTFail("Erwartet .decoding, war \(error)") }
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
    }

    func testHTTPErrorMapsServerMessage() async {
        StubURLProtocol.enqueue(statusCode: 401, json: #"{"error":{"code":"unauthorized","message":"Anmeldung erforderlich"}}"#)
        do {
            _ = try await client.currentUser()
            XCTFail("Erwartete ZunderError.http")
        } catch let error as ZunderError {
            XCTAssertEqual(error, .http(status: 401, message: "Anmeldung erforderlich"))
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
    }

    func testServerUnavailableIsRetryable() {
        XCTAssertTrue(ZunderError.http(status: 503, message: nil).isRetryable)
        XCTAssertTrue(ZunderError.http(status: 502, message: nil).isRetryable)
        XCTAssertFalse(ZunderError.http(status: 400, message: nil).isRetryable)
        XCTAssertFalse(ZunderError.notConfigured("x").isRetryable)
    }

    func testUnreadableErrorBodyHasNilMessage() async {
        StubURLProtocol.enqueue(statusCode: 500, data: Data("<html>oops</html>".utf8))
        await assertThrows(ZunderError.http(status: 500, message: nil)) {
            _ = try await self.client.currentUser()
        }
    }

    // MARK: - Abhaken

    func testCompleteTaskSendsSingleDoneOpAboveServerState() async throws {
        let taskID = "01929c3e-0000-7000-8000-000000000001"
        let opID = "01929c3e-0000-7000-8000-0000000000aa"
        // Server-Stand liegt (Uhrenabweichung) 5 s nach der lokalen Uhr.
        let serverUpdated = Self.fixedNow.addingTimeInterval(5)
        let fixedFactory = ZunderOpFactory(
            node: Self.node, clock: HybridLogicalClock(), now: { Self.fixedNow },
            makeID: { _ in opID }
        )
        let fixedClient = ZunderClient(
            secrets: MockSecretStore(values: [.zunderToken: Self.token]),
            baseURL: { Self.base }, factory: fixedFactory, session: session, calendar: calendar
        )
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"accepted":["\#(opID)"],"rejected":[],"warnings":[],"cursor":10}"#)

        try await fixedClient.completeTask(id: taskID, notBefore: serverUpdated)

        let body = try lastBodyJSON()
        let ops = try XCTUnwrap(body["ops"] as? [[String: Any]])
        XCTAssertEqual(ops.count, 1)
        let op = try XCTUnwrap(ops.first)
        XCTAssertEqual(op["op_id"] as? String, opID)
        XCTAssertEqual(op["entity"] as? String, "task")
        XCTAssertEqual(op["entity_id"] as? String, taskID)
        XCTAssertEqual(op["field"] as? String, "status")
        XCTAssertEqual(op["value"] as? String, "done")
        let hlc = try XCTUnwrap(op["hlc"] as? String)
        XCTAssertTrue(matches(hlc, Self.hlcPattern), hlc)
        let wall = try XCTUnwrap(UInt64(hlc.prefix(13)))
        XCTAssertGreaterThan(wall, UInt64(serverUpdated.timeIntervalSince1970 * 1000), "HLC muss über dem Server-Stand liegen")
    }

    // MARK: - Heute (MCP filter_tasks)

    func testTodayTasksRequestShape() async throws {
        StubURLProtocol.enqueue(statusCode: 200, json: mcpResult(tasks: "[]"))
        _ = try await client.todayTasks(now: Self.fixedNow)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://zunder.example/mcp")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json, text/event-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "MCP-Protocol-Version"), "2025-06-18")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(Self.token)")

        let body = try lastBodyJSON()
        XCTAssertEqual(body["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(body["method"] as? String, "tools/call")
        XCTAssertNotNil(body["id"])
        let params = try XCTUnwrap(body["params"] as? [String: Any])
        XCTAssertEqual(params["name"] as? String, "filter_tasks")
        let arguments = try XCTUnwrap(params["arguments"] as? [String: Any])
        XCTAssertEqual(arguments["due_before"] as? String, "2026-10-12", "Lokaler Kalendertag")
        XCTAssertEqual(arguments["status"] as? [String], ["open", "in_progress", "blocked"])
        XCTAssertEqual(arguments["order_by"] as? String, "due")
        XCTAssertEqual(arguments["limit"] as? Int, 200)
        XCTAssertEqual(Set(arguments.keys), ["due_before", "status", "order_by", "limit"])
    }

    func testTodayTasksParsesDateOnlyAndRFC3339Due() async throws {
        let tasks = """
        [
          {"id":"01929c3e-0000-7000-8000-000000000001","title":"Rechnung zahlen","status":"open",
           "due":"2026-10-11","location":{"kind":"inbox"},
           "updated_at":"2026-10-10T07:00:00.250Z","type":"aufgabe","progress":{"done":0,"total":0}},
          {"id":"01929c3e-0000-7000-8000-000000000002","title":"Review vorbereiten","status":"in_progress",
           "due":"2026-10-12T09:30:00+02:00",
           "location":{"kind":"project","id":"p1","name":"Funke","area_id":"a1","area_name":"Software"},
           "updated_at":"2026-10-11T12:00:00Z"},
          {"id":"01929c3e-0000-7000-8000-000000000003","title":"Ohne Datum","status":"blocked",
           "due":null,"location":{"kind":"area","id":"a1","name":"Haushalt"}}
        ]
        """
        StubURLProtocol.enqueue(statusCode: 200, json: mcpResult(tasks: tasks))
        let result = try await client.todayTasks(now: Self.fixedNow)
        XCTAssertEqual(result.count, 3)

        let first = result[0]
        XCTAssertEqual(first.title, "Rechnung zahlen")
        XCTAssertEqual(first.status, "open")
        XCTAssertEqual(first.locationName, "Inbox")
        var day = DateComponents()
        day.year = 2026; day.month = 10; day.day = 11
        XCTAssertEqual(first.due, .day(try XCTUnwrap(calendar.date(from: day))))
        XCTAssertEqual(first.updatedAt, Date(timeIntervalSince1970: 1_791_615_600.25))
        XCTAssertEqual(first.webURL?.absoluteString, "https://zunder.example/#/aufgabe/01929c3e-0000-7000-8000-000000000001")
        XCTAssertTrue(first.isOverdue(referenceDate: Self.fixedNow, calendar: calendar))

        let second = result[1]
        XCTAssertEqual(second.due, .dateTime(Date(timeIntervalSince1970: 1_791_790_200)))
        XCTAssertEqual(second.locationName, "Software › Funke")
        XCTAssertEqual(second.statusLabel, "In Arbeit")
        XCTAssertFalse(second.isOverdue(referenceDate: Self.fixedNow, calendar: calendar))

        let third = result[2]
        XCTAssertNil(third.due)
        XCTAssertEqual(third.locationName, "Haushalt")
        XCTAssertNil(third.updatedAt)
    }

    func testTodayTasksToolErrorThrowsRejected() async {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"Unbekannter Parameter: due_before"}],
         "structuredContent":{"error":{"code":"invalid_arguments","message":"Unbekannter Parameter: due_before"}},
         "isError":true}}
        """
        StubURLProtocol.enqueue(statusCode: 200, json: json)
        await assertThrows(ZunderError.rejected("Unbekannter Parameter: due_before")) {
            _ = try await self.client.todayTasks(now: Self.fixedNow)
        }
    }

    func testTodayTasksJSONRPCErrorThrows() async {
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"Unbekanntes Werkzeug"}}"#)
        await assertThrows(ZunderError.rejected("MCP-Fehler -32602: Unbekanntes Werkzeug")) {
            _ = try await self.client.todayTasks(now: Self.fixedNow)
        }
    }

    func testTodayTasksAcceptsSSEFraming() async throws {
        let payload = mcpResult(tasks: #"[{"id":"t1","title":"SSE","status":"open","due":"2026-10-12","location":{"kind":"loose"}}]"#)
            .replacingOccurrences(of: "\n", with: " ")
        StubURLProtocol.enqueue(
            statusCode: 200,
            json: "event: message\ndata: \(payload)\n\n",
            headers: ["Content-Type": "text/event-stream"]
        )
        let result = try await client.todayTasks(now: Self.fixedNow)
        XCTAssertEqual(result.map(\.title), ["SSE"])
        XCTAssertEqual(result.first?.locationName, "Lose")
    }

    // MARK: - Op-Fabrik / HLC / UUIDv7

    func testUUIDv7Format() {
        for _ in 0..<50 {
            let id = UUIDv7.generate(at: Self.fixedNow)
            XCTAssertTrue(matches(id, Self.uuidV7Pattern), "Kein UUIDv7: \(id)")
        }
        // Die ersten 48 Bit tragen die Millisekunden.
        let id = UUIDv7.generate(at: Self.fixedNow)
        let hex = id.replacingOccurrences(of: "-", with: "").prefix(12)
        XCTAssertEqual(UInt64(hex, radix: 16), UInt64(Self.fixedNow.timeIntervalSince1970 * 1000))
    }

    func testHLCIsStrictlyIncreasingAndPadded() {
        let clock = HybridLogicalClock()
        let a = clock.next(now: Self.fixedNow)
        let b = clock.next(now: Self.fixedNow)
        let c = clock.next(now: Self.fixedNow.addingTimeInterval(-10))   // Uhr springt zurück
        XCTAssertEqual(a.counter, 0)
        XCTAssertEqual(b.wallMs, a.wallMs)
        XCTAssertEqual(b.counter, 1)
        XCTAssertEqual(c.wallMs, a.wallMs, "max(physisch, letzter)")
        XCTAssertEqual(c.counter, 2)

        let formatted = HybridLogicalClock.format(wallMs: 42, counter: 7, node: "funke-0a1b2c3d")
        XCTAssertEqual(formatted, "0000000000042:00007:funke-0a1b2c3d")
        let hlcs = [a, b, c].map { HybridLogicalClock.format(wallMs: $0.wallMs, counter: $0.counter, node: Self.node) }
        XCTAssertEqual(hlcs, hlcs.sorted(), "Lexikografische Ordnung = Erzeugungsreihenfolge")
    }

    func testNodeIDFormat() {
        let node = ZunderNodeID.make()
        XCTAssertTrue(matches(node, "^funke-[0-9a-f]{8}$"), node)
        XCTAssertTrue(ZunderNodeID.isValid(node))
        XCTAssertFalse(ZunderNodeID.isValid("Funke_X"))
    }

    // MARK: - Helfer

    private static func makeFactory() -> ZunderOpFactory {
        ZunderOpFactory(node: node, clock: HybridLogicalClock(), now: { fixedNow })
    }

    private func makeClient(secrets: SecretStoring, base: String = ZunderClientTests.base) -> ZunderClient {
        ZunderClient(secrets: secrets, baseURL: { base }, factory: factory, session: session, calendar: calendar)
    }

    private func acceptAll(_ ops: [ZunderOp]) -> String {
        let ids = ops.map { "\"\($0.opID)\"" }.joined(separator: ",")
        return #"{"accepted":[\#(ids)],"rejected":[],"warnings":[],"cursor":42}"#
    }

    private func mcpResult(tasks: String) -> String {
        """
        {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"…"}],
         "structuredContent":{"tasks":\(tasks),"count":0,"total":0,"offset":0,"truncated":false,"next_offset":null},
         "isError":false}}
        """
    }

    private func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private func lastBodyJSON() throws -> [String: Any] {
        let data = try XCTUnwrap(StubURLProtocol.lastRequestBody, "Kein Request-Body erfasst")
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any], "Body ist kein JSON-Objekt")
    }

    private func assertThrows(
        _ expected: ZunderError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: () async throws -> Void
    ) async {
        do {
            try await block()
            XCTFail("Erwarteter Fehler \(expected) wurde nicht geworfen.", file: file, line: line)
        } catch let error as ZunderError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unerwarteter Fehlertyp: \(error)", file: file, line: line)
        }
    }
}

// MARK: - Test-Mocks (privat zu dieser Datei)

private struct MockSecretStore: SecretStoring {
    private let values: [SecretKey: String]

    init(values: [SecretKey: String]) {
        self.values = values
    }

    func string(for key: SecretKey) -> String? {
        values[key]
    }

    func setString(_ value: String?, for key: SecretKey) throws {
        // Für diese Tests nicht benötigt.
    }
}
