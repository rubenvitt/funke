import Foundation

/// KI-Provider auf Basis der Anthropic Messages API (`claude-haiku-4-5`).
///
/// Nutzt strukturierte Ausgaben über `output_config.format` mit dem geteilten
/// JSON-Schema. Schlüssel kommt ausschließlich über `SecretStoring`; er wird
/// nie geloggt. Fehler werden sichtbar als `EnrichmentError` geworfen.
struct AnthropicProvider: AIEnrichmentProvider {
    let kind: EnrichmentProviderKind = .anthropic

    private let secrets: SecretStoring
    private let session: URLSession
    private let model: String

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let anthropicVersion = "2023-06-01"
    private static let maxTokens = 1024

    init(secrets: SecretStoring, session: URLSession = .shared, model: String = "claude-haiku-4-5") {
        self.secrets = secrets
        self.session = session
        self.model = model
    }

    func availability() async -> ProviderAvailability {
        secrets.hasValue(for: .anthropicKey)
            ? .available
            : .unavailable("Kein Anthropic-Schlüssel hinterlegt.")
    }

    func enrich(_ rawText: String) async throws -> EnrichmentSuggestion {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EnrichmentError.emptyInput }

        guard let key = secrets.string(for: .anthropicKey), !key.isEmpty else {
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
            "system": EnrichmentPrompt.systemInstruction,
            "messages": [
                ["role": "user", "content": rawText]
            ],
            "output_config": [
                "format": [
                    "type": "json_schema",
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
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
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

    private struct MessagesResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        let content: [ContentBlock]
        let stop_reason: String?
    }

    private static func suggestion(from data: Data) throws -> EnrichmentSuggestion {
        let decoded: MessagesResponse
        do {
            decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw EnrichmentError.invalidResponse("Antwort nicht dekodierbar: \(error.localizedDescription)")
        }

        if decoded.stop_reason == "refusal" {
            throw EnrichmentError.invalidResponse("KI-Anfrage wurde abgelehnt")
        }

        guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw EnrichmentError.invalidResponse("Keine Textantwort im Ergebnis.")
        }

        return try EnrichmentResponseParser.parse(text)
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
