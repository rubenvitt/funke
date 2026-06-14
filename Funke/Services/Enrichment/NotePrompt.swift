import Foundation

/// Geteilter Prompt + Schema + toleranter Parser für die KI-Notizbereinigung.
/// Anthropic und OpenRouter nutzen denselben System-Prompt und Parser;
/// die Apple-Provider nutzen denselben System-Prompt als `instructions`.
///
/// Spiegelt `EnrichmentPrompt`, zielt aber auf saubere Notizen statt Aufgaben.
enum NotePrompt {
    /// System-Anweisung. Bereinigt, formatiert — fügt aber NICHTS hinzu.
    static let systemInstruction = """
    Bereinige eine rohe oder per Sprache erfasste Notiz zu sauberem Markdown. \
    Liefere einen knappen Titel und einen aufgeräumten Body. Korrigiere \
    offensichtliche Tipp-/Erkennungsfehler und formatiere sinnvoll \
    (Absätze/Listen), aber FÜGE KEINE Informationen hinzu und bewahre die \
    Bedeutung. Antworte ausschließlich als JSON-Objekt {"title": string, \
    "body": string} ohne Codeblock.
    """

    /// JSON-Schema-String für strukturierte Ausgaben (Anthropic output_config /
    /// OpenRouter response_format). Beide Felder required.
    static let jsonSchemaString = """
    {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "title": { "type": "string" },
        "body": { "type": "string" }
      },
      "required": ["title", "body"]
    }
    """

    static func userPrompt(for rawText: String) -> String {
        "Notiz:\n\(rawText)"
    }
}

/// Tolerant gegenüber Code-Fences, Vor-/Nachtext. Nutzt dieselbe
/// JSON-Extraktion wie `EnrichmentResponseParser`. Wirft sichtbare Fehler.
enum NoteResponseParser {
    private struct Raw: Decodable {
        let title: String?
        let body: String?
    }

    static func parse(_ raw: String) throws -> NoteSuggestion {
        guard let json = EnrichmentResponseParser.extractJSONObject(from: raw),
              let data = json.data(using: .utf8) else {
            throw EnrichmentError.invalidResponse("Keine JSON-Struktur in der Antwort gefunden.")
        }
        let decoded: Raw
        do {
            decoded = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw EnrichmentError.invalidResponse("JSON nicht dekodierbar: \(error.localizedDescription)")
        }

        let title = (decoded.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw EnrichmentError.invalidResponse("KI-Antwort ohne Titel.")
        }

        let body = (decoded.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Fehlender/leerer Body → auf den Titel zurückfallen, nie verlieren.
        return NoteSuggestion(title: title, body: body.isEmpty ? title : body)
    }
}
