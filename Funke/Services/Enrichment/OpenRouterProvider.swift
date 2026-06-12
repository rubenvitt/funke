import Foundation

/// KI-Provider auf Basis der OpenRouter Chat-Completions-API.
///
/// Nutzt strukturierte Ausgaben über `response_format` mit dem geteilten
/// JSON-Schema (`strict: true`). Das Modell wird injiziert (kein Default).
/// Schlüssel kommt ausschließlich über `SecretStoring`; er wird nie geloggt.
struct OpenRouterProvider: AIEnrichmentProvider {
    let kind: EnrichmentProviderKind = .openRouter

    private let secrets: SecretStoring
    private let session: URLSession
    private let model: String

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private static let referer = "https://github.com/rubeen/funke"
    private static let title = "Funke"
    private static let maxTokens = 512

    init(secrets: SecretStoring, session: URLSession = .shared, model: String) {
        self.secrets = secrets
        self.session = session
        self.model = model
    }

    func availability() async -> ProviderAvailability {
        secrets.hasValue(for: .openRouterKey)
            ? .available
            : .unavailable("Kein OpenRouter-Schlüssel hinterlegt.")
    }

    func enrich(_ rawText: String) async throws -> EnrichmentSuggestion {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EnrichmentError.emptyInput }

        guard let key = secrets.string(for: .openRouterKey), !key.isEmpty else {
            throw EnrichmentError.missingAPIKey(provider: kind.displayName)
        }

        let request = try makeRequest(key: key, rawText: rawText)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw EnrichmentError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw EnrichmentError.invalidResponse("Keine HTTP-Antwort erhalten.")
        }

        guard (200...299).contains(http.statusCode) else {
            throw EnrichmentError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }

        return try Self.suggestion(from: data)
    }

    // MARK: - Request

    private func makeRequest(key: String, rawText: String) throws -> URLRequest {
        let schema = try Self.schemaObject()

        let body: [String: Any] = [
            "model": model,
            "max_tokens": Self.maxTokens,
            "messages": [
                ["role": "system", "content": EnrichmentPrompt.systemInstruction],
                ["role": "user", "content": rawText]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "task",
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]

        let payload: Data
        do {
            payload = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw EnrichmentError.invalidResponse("Anfrage konnte nicht serialisiert werden: \(error.localizedDescription)")
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.referer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(Self.title, forHTTPHeaderField: "X-Title")
        request.httpBody = payload
        return request
    }

    /// Schält das geteilte JSON-Schema in ein eingebettetes JSON-Objekt.
    private static func schemaObject() throws -> [String: Any] {
        guard let schemaData = EnrichmentPrompt.jsonSchemaString.data(using: .utf8) else {
            throw EnrichmentError.invalidResponse("JSON-Schema konnte nicht kodiert werden.")
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: schemaData)
        } catch {
            throw EnrichmentError.invalidResponse("JSON-Schema nicht lesbar: \(error.localizedDescription)")
        }
        guard let dictionary = object as? [String: Any] else {
            throw EnrichmentError.invalidResponse("JSON-Schema ist kein Objekt.")
        }
        return dictionary
    }

    // MARK: - Response

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private static func suggestion(from data: Data) throws -> EnrichmentSuggestion {
        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw EnrichmentError.invalidResponse("Antwort nicht dekodierbar: \(error.localizedDescription)")
        }

        guard let content = decoded.choices.first?.message.content else {
            throw EnrichmentError.invalidResponse("Keine Textantwort im Ergebnis.")
        }

        return try EnrichmentResponseParser.parse(content)
    }

    /// Liest `{"error":{"message":...}}` aus dem Fehlerkörper; sonst `nil`.
    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String,
              !message.isEmpty else {
            return nil
        }
        return message
    }
}
