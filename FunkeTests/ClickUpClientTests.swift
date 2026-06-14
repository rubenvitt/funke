import XCTest
@testable import Funke

final class ClickUpClientTests: XCTestCase {

    private var session: URLSession!
    private var secrets: MockSecretStore!
    private var client: ClickUpClient!

    private static let token = "pk_12345_ABCDEF"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = StubURLProtocol.makeSession()
        secrets = MockSecretStore(values: [.clickUpToken: Self.token])
        client = ClickUpClient(secrets: secrets, session: session)
    }

    override func tearDown() {
        StubURLProtocol.reset()
        session = nil
        secrets = nil
        client = nil
        super.tearDown()
    }

    // MARK: - Token / Header

    func testMissingTokenThrows() async {
        let emptySecrets = MockSecretStore(values: [:])
        let emptyClient = ClickUpClient(secrets: emptySecrets, session: session)
        do {
            _ = try await emptyClient.authorizedUser()
            XCTFail("Erwartete ClickUpError.missingToken")
        } catch let error as ClickUpError {
            XCTAssertEqual(error, .missingToken)
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
    }

    func testAuthorizationHeaderHasNoBearerPrefix() async throws {
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"user":{"id":42,"username":"ruben"}}"#)
        _ = try await client.authorizedUser()

        let header = StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(header, Self.token)
        XCTAssertFalse(header?.hasPrefix("Bearer") ?? true, "Token darf KEIN Bearer-Präfix tragen")
        XCTAssertEqual(
            StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
    }

    // MARK: - authorizedUser (user-Wrapper)

    func testAuthorizedUserParsesWrappedUser() async throws {
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"user":{"id":42,"username":"ruben"}}"#)
        let user = try await client.authorizedUser()
        XCTAssertEqual(user.id, 42)
        XCTAssertEqual(user.username, "ruben")
        XCTAssertTrue(
            StubURLProtocol.lastRequest?.url?.absoluteString.hasSuffix("/api/v2/user") ?? false,
            "URL sollte auf /api/v2/user enden, war: \(StubURLProtocol.lastRequest?.url?.absoluteString ?? "nil")"
        )
    }

    // MARK: - teams / spaces / folders / lists (URL-Pfade)

    func testTeamsURLAndParsing() async throws {
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"teams":[{"id":"t1","name":"Workspace"}]}"#)
        let teams = try await client.teams()
        XCTAssertEqual(teams, [ClickUpTeam(id: "t1", name: "Workspace")])
        XCTAssertTrue(lastURLString().hasSuffix("/api/v2/team"))
    }

    func testSpacesURLIncludesArchivedFalse() async throws {
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"spaces":[{"id":"s1","name":"Space"}]}"#)
        let spaces = try await client.spaces(teamID: "t1")
        XCTAssertEqual(spaces, [ClickUpSpace(id: "s1", name: "Space")])
        XCTAssertTrue(lastURLString().contains("/api/v2/team/t1/space"))
        XCTAssertTrue(lastURLString().contains("archived=false"))
    }

    func testFolderlessListsURL() async throws {
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"lists":[{"id":"l1","name":"Inbox"}]}"#)
        let lists = try await client.folderlessLists(spaceID: "s1")
        XCTAssertEqual(lists, [ClickUpList(id: "l1", name: "Inbox")])
        XCTAssertTrue(lastURLString().contains("/api/v2/space/s1/list"))
    }

    func testFolderListsURL() async throws {
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"lists":[{"id":"l2","name":"Tasks"}]}"#)
        let lists = try await client.folderLists(folderID: "f1")
        XCTAssertEqual(lists, [ClickUpList(id: "l2", name: "Tasks")])
        XCTAssertTrue(lastURLString().contains("/api/v2/folder/f1/list"))
    }

    // MARK: - createTask (Body inkl. markdown_content + Integer-Priorität)

    func testCreateTaskBodyContainsMarkdownContentAndIntegerPriority() async throws {
        StubURLProtocol.enqueue(statusCode: 200, json: "{}")
        try await client.createTask(
            listID: "l1",
            name: "Bericht schreiben",
            markdownDescription: "**wichtig**",
            priority: .high
        )

        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertTrue(lastURLString().hasSuffix("/api/v2/list/l1/task"))

        let body = try lastBodyJSON()
        XCTAssertEqual(body["name"] as? String, "Bericht schreiben")
        // Feld heißt markdown_content (nicht markdown_description).
        XCTAssertEqual(body["markdown_content"] as? String, "**wichtig**")
        XCTAssertNil(body["markdown_description"], "Falscher Markdown-Feldname")
        // Priorität als Integer (high == 2), nicht als String/Objekt.
        XCTAssertEqual(body["priority"] as? Int, 2)
        XCTAssertNil(body["tags"], "tags wurden entfernt und dürfen nicht im Body stehen")
    }

    func testCreateTaskOmitsPriorityAndMarkdownWhenNil() async throws {
        StubURLProtocol.enqueue(statusCode: 200, json: "{}")
        try await client.createTask(
            listID: "l1",
            name: "Nur Titel",
            markdownDescription: nil,
            priority: nil
        )

        let body = try lastBodyJSON()
        XCTAssertEqual(body["name"] as? String, "Nur Titel")
        XCTAssertNil(body["priority"], "priority muss bei nil weggelassen werden")
        XCTAssertNil(body["markdown_content"], "markdown_content muss bei nil weggelassen werden")
        XCTAssertNil(body["tags"], "tags wurden entfernt und dürfen nicht im Body stehen")
    }

    // MARK: - todayTasks (due_date_lt mit fixem now)

    func testTodayTasksDueDateLtIsStartOfTomorrowInMilliseconds() async throws {
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"tasks":[]}"#)

        // Fixer Zeitpunkt: 2026-06-12 13:30:00 UTC.
        let now = Date(timeIntervalSince1970: 1_781_271_000)
        _ = try await client.todayTasks(teamID: "t1", assigneeID: 42, now: now)

        // Erwartungswert mit derselben Logik wie der Client ableiten
        // (kalenderabhängig -> nie hartkodieren).
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let expectedMs = Int(startOfTomorrow.timeIntervalSince1970 * 1000)

        let components = URLComponents(
            url: StubURLProtocol.lastRequest!.url!,
            resolvingAgainstBaseURL: false
        )
        let queryValue = components?.queryItems?.first { $0.name == "due_date_lt" }?.value
        XCTAssertEqual(queryValue, String(expectedMs))

        // Übrige Query-Parameter prüfen.
        func value(_ name: String) -> String? {
            components?.queryItems?.first { $0.name == name }?.value
        }
        XCTAssertEqual(value("assignees[]"), "42")
        XCTAssertEqual(value("include_closed"), "false")
        XCTAssertEqual(value("order_by"), "due_date")
        XCTAssertEqual(value("subtasks"), "false")
        XCTAssertTrue(lastURLString().contains("/api/v2/team/t1/task"))
    }

    // MARK: - todayTasks (Parsing: due_date-String, priority-Objekt, list)

    func testTodayTasksParsesStringDueDatePriorityObjectAndList() async throws {
        // due_date als ms-String, priority als Objekt mit Label, list als {id,name}.
        let json = """
        {"tasks":[
          {"id":"abc","name":"Aufgabe",
           "url":"https://app.clickup.com/t/abc",
           "status":{"status":"to do","type":"open"},
           "due_date":"1700000000000",
           "priority":{"priority":"high","id":"2"},
           "list":{"id":"l9","name":"Projekt"}}
        ]}
        """
        StubURLProtocol.enqueue(statusCode: 200, json: json)

        let tasks = try await client.todayTasks(teamID: "t1", assigneeID: 42, now: Date())
        XCTAssertEqual(tasks.count, 1)
        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "abc")
        XCTAssertEqual(task.name, "Aufgabe")
        XCTAssertEqual(task.url, "https://app.clickup.com/t/abc")
        XCTAssertEqual(task.statusName, "to do")
        XCTAssertEqual(task.statusType, "open")
        // due_date: ms-String -> Date(timeIntervalSince1970: ms/1000)
        XCTAssertEqual(task.dueDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.listID, "l9")
        XCTAssertEqual(task.listName, "Projekt")
    }

    func testTodayTasksHandlesNullDueDateAndNullPriority() async throws {
        let json = """
        {"tasks":[
          {"id":"x","name":"Ohne Daten",
           "status":{"status":"open","type":"open"},
           "due_date":null,"priority":null,"list":null,"url":null}
        ]}
        """
        StubURLProtocol.enqueue(statusCode: 200, json: json)

        let tasks = try await client.todayTasks(teamID: "t1", assigneeID: 42, now: Date())
        let task = try XCTUnwrap(tasks.first)
        XCTAssertNil(task.dueDate)
        XCTAssertNil(task.priority)
        XCTAssertNil(task.listID)
        XCTAssertNil(task.listName)
        XCTAssertNil(task.url)
    }

    func testTodayTasksPriorityFallsBackToIdWhenLabelMissing() async throws {
        // priority.priority fehlt -> Fallback über id-String -> Int -> Priority(clickUpValue:)
        let json = """
        {"tasks":[
          {"id":"y","name":"Nur ID-Prio",
           "status":{"status":"open","type":"open"},
           "due_date":null,
           "priority":{"priority":null,"id":"1"},
           "list":null,"url":null}
        ]}
        """
        StubURLProtocol.enqueue(statusCode: 200, json: json)

        let tasks = try await client.todayTasks(teamID: "t1", assigneeID: 42, now: Date())
        XCTAssertEqual(tasks.first?.priority, .urgent) // id "1" == urgent
    }

    // MARK: - listStatuses

    func testListStatusesParsesStatusArray() async throws {
        let json = """
        {"id":"l1","name":"Inbox","statuses":[
          {"status":"to do","type":"open","orderindex":0},
          {"status":"erledigt","type":"closed","orderindex":1}
        ]}
        """
        StubURLProtocol.enqueue(statusCode: 200, json: json)

        let statuses = try await client.listStatuses(listID: "l1")
        XCTAssertEqual(statuses, [
            ClickUpStatusInfo(name: "to do", type: "open"),
            ClickUpStatusInfo(name: "erledigt", type: "closed")
        ])
        XCTAssertEqual(statuses.doneStatus(), ClickUpStatusInfo(name: "erledigt", type: "closed"))
        XCTAssertTrue(lastURLString().hasSuffix("/api/v2/list/l1"))
    }

    // MARK: - setStatus (PUT-Body)

    func testSetStatusSendsPutWithStatusBody() async throws {
        StubURLProtocol.enqueue(statusCode: 200, json: "{}")
        try await client.setStatus(taskID: "abc", status: "erledigt")

        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "PUT")
        XCTAssertTrue(lastURLString().hasSuffix("/api/v2/task/abc"))
        let body = try lastBodyJSON()
        XCTAssertEqual(body["status"] as? String, "erledigt")
    }

    // MARK: - Fehler-Mapping (401 / 404 mit err)

    func testUnauthorizedMapsToHttpErrorWithMessage() async {
        StubURLProtocol.enqueue(
            statusCode: 401,
            json: #"{"err":"Token invalid","ECODE":"OAUTH_017"}"#
        )
        do {
            _ = try await client.authorizedUser()
            XCTFail("Erwartete ClickUpError.http")
        } catch let error as ClickUpError {
            XCTAssertEqual(error, .http(status: 401, message: "Token invalid"))
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
    }

    func testNotFoundMapsToHttpErrorWithMessage() async {
        StubURLProtocol.enqueue(
            statusCode: 404,
            json: #"{"err":"List not found","ECODE":"LIST_011"}"#
        )
        do {
            try await client.createTask(
                listID: "missing",
                name: "x",
                markdownDescription: nil,
                priority: nil
            )
            XCTFail("Erwartete ClickUpError.http")
        } catch let error as ClickUpError {
            XCTAssertEqual(error, .http(status: 404, message: "List not found"))
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
    }

    func testHttpErrorWithUnparseableBodyHasNilMessage() async {
        StubURLProtocol.enqueue(statusCode: 500, data: Data("<html>oops</html>".utf8))
        do {
            _ = try await client.teams()
            XCTFail("Erwartete ClickUpError.http")
        } catch let error as ClickUpError {
            XCTAssertEqual(error, .http(status: 500, message: nil))
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
    }

    // MARK: - Decoding-Fehler

    func testDecodingErrorMapsToClickUpDecoding() async {
        StubURLProtocol.enqueue(statusCode: 200, json: #"{"unerwartet":true}"#)
        do {
            _ = try await client.authorizedUser()
            XCTFail("Erwartete ClickUpError.decoding")
        } catch let error as ClickUpError {
            guard case .decoding = error else {
                return XCTFail("Erwartete .decoding, war \(error)")
            }
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
    }

    // MARK: - Helfer

    private func lastURLString() -> String {
        StubURLProtocol.lastRequest?.url?.absoluteString ?? ""
    }

    private func lastBodyJSON() throws -> [String: Any] {
        let data = try XCTUnwrap(StubURLProtocol.lastRequestBody, "Kein Request-Body erfasst")
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any], "Body ist kein JSON-Objekt")
    }
}

// MARK: - Test-Mocks (privat zu dieser Datei)

private final class MockSecretStore: SecretStoring {
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
