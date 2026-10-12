import XCTest
@testable import Funke

/// Tests für den KI-Veredelungs-Layer: der geteilte Parser sowie die beiden
/// HTTP-Provider (Anthropic, OpenRouter) über `StubURLProtocol`.
///
/// `StubURLProtocol` liegt unter `FunkeTests/Support/StubURLProtocol.swift` und
/// wird hier nur benutzt, nicht neu definiert.
final class EnrichmentTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - EnrichmentResponseParser

    func testParserCleanJSON() throws {
        let raw = #"{"title": "Müll rausbringen", "details": "Dienstagabend"}"#
        let suggestion = try EnrichmentResponseParser.parse(raw)
        XCTAssertEqual(suggestion.title, "Müll rausbringen")
        XCTAssertEqual(suggestion.details, "Dienstagabend")
    }

    func testParserCodeFences() throws {
        let raw = """
        ```json
        {"title": "Bericht schreiben", "details": ""}
        ```
        """
        let suggestion = try EnrichmentResponseParser.parse(raw)
        XCTAssertEqual(suggestion.title, "Bericht schreiben")
        // Leere Strings → nil
        XCTAssertNil(suggestion.details)
    }

    func testParserSurroundingProse() throws {
        let raw = """
        Hier ist deine Aufgabe:
        {"title": "Arzttermin", "details": "Hausarzt anrufen"}
        Viel Erfolg!
        """
        let suggestion = try EnrichmentResponseParser.parse(raw)
        XCTAssertEqual(suggestion.title, "Arzttermin")
        XCTAssertEqual(suggestion.details, "Hausarzt anrufen")
    }

    func testParserDescriptionKeyAlias() throws {
        // „description" wird als Alias für „details" akzeptiert.
        let raw = #"{"title": "Einkaufen", "description": "Milch und Brot"}"#
        let suggestion = try EnrichmentResponseParser.parse(raw)
        XCTAssertEqual(suggestion.title, "Einkaufen")
        XCTAssertEqual(suggestion.details, "Milch und Brot")
    }

    func testParserMissingTitleThrows() {
        let raw = #"{"details": "Etwas"}"#
        XCTAssertThrowsError(try EnrichmentResponseParser.parse(raw)) { error in
            guard case EnrichmentError.invalidResponse = error else {
                return XCTFail("Erwartete .invalidResponse, bekam \(error)")
            }
        }
    }

    func testParserIgnoresLegacyPriorityKey() throws {
        // Ältere Modelle/Prompts liefern evtl. noch `priority` – wird ignoriert.
        let raw = #"{"title": "Aufgabe", "details": "", "priority": "urgent"}"#
        let suggestion = try EnrichmentResponseParser.parse(raw)
        XCTAssertEqual(suggestion, EnrichmentSuggestion(title: "Aufgabe", details: nil))
    }

    func testSchemasNoLongerContainPriority() {
        XCTAssertFalse(EnrichmentPrompt.jsonSchemaString.contains("priority"))
        XCTAssertFalse(ClassifyPrompt.jsonSchemaString.contains("priority"))
        XCTAssertFalse(EnrichmentPrompt.systemInstruction.contains("Priorität"))
        XCTAssertFalse(ClassifyPrompt.systemInstruction.contains("Priorität"))
    }

    // MARK: - ClassifyResponseParser

    func testClassifyParserReadsKindTitleBody() throws {
        let raw = #"{"kind": "task", "title": "Zahnarzt", "body": "anrufen", "priority": "high"}"#
        let result = try ClassifyResponseParser.parse(raw)
        XCTAssertEqual(result, CaptureClassification(kind: .task, title: "Zahnarzt", body: "anrufen"))
    }

    func testClassifyParserUnknownKindFallsBackToNote() throws {
        let raw = #"{"kind": "irgendwas", "title": "Gedanke", "body": ""}"#
        let result = try ClassifyResponseParser.parse(raw)
        XCTAssertEqual(result.kind, .note)
        XCTAssertEqual(result.body, "Gedanke", "Leerer Body fällt auf den Titel zurück")
    }

    // MARK: - Anthropic: Request-Bau

    func testAnthropicRequestBuilding() async throws {
        StubURLProtocol.enqueue(
            statusCode: 200,
            json: anthropicSuccessJSON(title: "Test")
        )
        let secrets = MockSecretStore(values: [.anthropicKey: "sk-ant-test"])
        let provider = AnthropicProvider(secrets: secrets, session: StubURLProtocol.makeSession())

        _ = try await provider.enrich("Roher Text")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try bodyObject(StubURLProtocol.lastRequestBody)
        XCTAssertEqual(body["model"] as? String, "claude-haiku-4-5")
        XCTAssertEqual(body["system"] as? String, EnrichmentPrompt.systemInstruction)

        // Schema ist als JSON-Objekt eingebettet (nicht als String).
        let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any])
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["type"] as? String, "object")

        // user-Message trägt den Rohtext.
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "Roher Text")
    }

    // MARK: - Anthropic: Response-Parsing

    func testAnthropicResponseParsing() async throws {
        StubURLProtocol.enqueue(
            statusCode: 200,
            json: anthropicSuccessJSON(title: "Steuererklärung")
        )
        let secrets = MockSecretStore(values: [.anthropicKey: "sk-ant-test"])
        let provider = AnthropicProvider(secrets: secrets, session: StubURLProtocol.makeSession())

        let suggestion = try await provider.enrich("egal")
        XCTAssertEqual(suggestion.title, "Steuererklärung")
    }

    func testAnthropicEmptyInputThrows() async {
        let secrets = MockSecretStore(values: [.anthropicKey: "sk-ant-test"])
        let provider = AnthropicProvider(secrets: secrets, session: StubURLProtocol.makeSession())
        await assertThrows(EnrichmentError.emptyInput) {
            _ = try await provider.enrich("   \n  ")
        }
    }

    func testAnthropicRefusalStopReasonThrows() async {
        let json = """
        {"content": [{"type": "text", "text": "egal"}], "stop_reason": "refusal"}
        """
        StubURLProtocol.enqueue(statusCode: 200, json: json)
        let secrets = MockSecretStore(values: [.anthropicKey: "sk-ant-test"])
        let provider = AnthropicProvider(secrets: secrets, session: StubURLProtocol.makeSession())

        await assertThrows(EnrichmentError.invalidResponse("KI-Anfrage wurde abgelehnt")) {
            _ = try await provider.enrich("Roher Text")
        }
    }

    func testAnthropicHTTPErrorMapsMessage() async {
        let json = #"{"error": {"type": "authentication_error", "message": "invalid x-api-key"}}"#
        StubURLProtocol.enqueue(statusCode: 401, json: json)
        let secrets = MockSecretStore(values: [.anthropicKey: "sk-ant-test"])
        let provider = AnthropicProvider(secrets: secrets, session: StubURLProtocol.makeSession())

        await assertThrows(EnrichmentError.http(status: 401, message: "invalid x-api-key")) {
            _ = try await provider.enrich("Roher Text")
        }
    }

    func testAnthropicMissingKeyThrows() async {
        let secrets = MockSecretStore(values: [:])
        let provider = AnthropicProvider(secrets: secrets, session: StubURLProtocol.makeSession())
        await assertThrows(EnrichmentError.missingAPIKey(provider: EnrichmentProviderKind.anthropic.displayName)) {
            _ = try await provider.enrich("Roher Text")
        }
    }

    // MARK: - OpenRouter: Request-Bau

    func testOpenRouterRequestBuilding() async throws {
        StubURLProtocol.enqueue(
            statusCode: 200,
            json: openRouterSuccessJSON(title: "Test")
        )
        let secrets = MockSecretStore(values: [.openRouterKey: "sk-or-test"])
        let provider = OpenRouterProvider(
            secrets: secrets,
            session: StubURLProtocol.makeSession(),
            model: "openai/gpt-5-nano"
        )

        _ = try await provider.enrich("Roher Text")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")

        let body = try bodyObject(StubURLProtocol.lastRequestBody)
        XCTAssertEqual(body["model"] as? String, "openai/gpt-5-nano")

        // response_format trägt name + strict + Schema-Objekt.
        let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["name"] as? String, "task")
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
        let schema = try XCTUnwrap(jsonSchema["schema"] as? [String: Any])
        XCTAssertEqual(schema["type"] as? String, "object")

        // system + user Messages.
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.first?["content"] as? String, EnrichmentPrompt.systemInstruction)
        XCTAssertEqual(messages.last?["role"] as? String, "user")
        XCTAssertEqual(messages.last?["content"] as? String, "Roher Text")
    }

    // MARK: - OpenRouter: Response-Parsing

    func testOpenRouterResponseParsing() async throws {
        StubURLProtocol.enqueue(
            statusCode: 200,
            json: openRouterSuccessJSON(title: "Rechnung zahlen")
        )
        let secrets = MockSecretStore(values: [.openRouterKey: "sk-or-test"])
        let provider = OpenRouterProvider(
            secrets: secrets,
            session: StubURLProtocol.makeSession(),
            model: "openai/gpt-5-nano"
        )

        let suggestion = try await provider.enrich("egal")
        XCTAssertEqual(suggestion.title, "Rechnung zahlen")
    }

    func testOpenRouterHTTPErrorMapsMessage() async {
        let json = #"{"error": {"message": "model not found", "code": 400}}"#
        StubURLProtocol.enqueue(statusCode: 400, json: json)
        let secrets = MockSecretStore(values: [.openRouterKey: "sk-or-test"])
        let provider = OpenRouterProvider(
            secrets: secrets,
            session: StubURLProtocol.makeSession(),
            model: "bad/model"
        )

        await assertThrows(EnrichmentError.http(status: 400, message: "model not found")) {
            _ = try await provider.enrich("Roher Text")
        }
    }

    func testOpenRouterEmptyInputThrows() async {
        let secrets = MockSecretStore(values: [.openRouterKey: "sk-or-test"])
        let provider = OpenRouterProvider(
            secrets: secrets,
            session: StubURLProtocol.makeSession(),
            model: "openai/gpt-5-nano"
        )
        await assertThrows(EnrichmentError.emptyInput) {
            _ = try await provider.enrich("")
        }
    }

    // MARK: - Test-Helfer

    /// Behauptet, dass der Block den erwarteten `EnrichmentError` wirft.
    private func assertThrows(
        _ expected: EnrichmentError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: () async throws -> Void
    ) async {
        do {
            try await block()
            XCTFail("Erwarteter Fehler \(expected) wurde nicht geworfen.", file: file, line: line)
        } catch let error as EnrichmentError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unerwarteter Fehlertyp: \(error)", file: file, line: line)
        }
    }

    private func bodyObject(_ data: Data?) throws -> [String: Any] {
        let data = try XCTUnwrap(data, "Request-Body fehlt.")
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any], "Body ist kein JSON-Objekt.")
    }

    private func anthropicSuccessJSON(title: String) -> String {
        let inner = #"{\"title\": \"\#(title)\", \"details\": \"\"}"#
        return """
        {"content": [{"type": "text", "text": "\(inner)"}], "stop_reason": "end_turn"}
        """
    }

    private func openRouterSuccessJSON(title: String) -> String {
        let inner = #"{\"title\": \"\#(title)\", \"details\": \"\"}"#
        return """
        {"choices": [{"message": {"content": "\(inner)"}}]}
        """
    }
}

// MARK: - Mocks

/// In-Memory-`SecretStoring` für Tests; nie loggend, kein Keychain.
private struct MockSecretStore: SecretStoring {
    private let values: [SecretKey: String]

    init(values: [SecretKey: String]) {
        self.values = values
    }

    func string(for key: SecretKey) -> String? {
        values[key]
    }

    func setString(_ value: String?, for key: SecretKey) throws {
        // Tests verändern keine Secrets; bewusst leer.
    }
}
