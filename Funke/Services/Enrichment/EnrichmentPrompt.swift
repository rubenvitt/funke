import Foundation

/// Geteilter Prompt + Schema + toleranter Parser für die KI-Veredelung.
/// Anthropic und OpenRouter nutzen denselben System-Prompt und Parser;
/// die Apple-Provider nutzen denselben System-Prompt als `instructions`.
enum EnrichmentPrompt {
    /// System-Anweisung. Robust gegen leere/kurze Eingaben.
    static let systemInstruction = """
    Du wandelst eine rohe Sprach- oder Textnotiz in eine knappe Aufgabe um.
    Antworte AUSSCHLIESSLICH mit einem einzigen JSON-Objekt – ohne Erklärung, \
    ohne Markdown-Codeblock – in genau dieser Form:
    {"title": "<knapper Titel>", "details": "<optionale Beschreibung oder leer>"}
    Antworte auf Deutsch, falls die Eingabe deutsch ist. Bei sehr kurzer Eingabe \
    nimm sie als Titel.
    """

    /// JSON-Schema-String für strukturierte Ausgaben (Anthropic output_config /
    /// OpenRouter response_format). Alle Felder required; optionale als leerer String.
    static let jsonSchemaString = """
    {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "title": { "type": "string" },
        "details": { "type": "string" }
      },
      "required": ["title", "details"]
    }
    """

    static func userPrompt(for rawText: String) -> String {
        "Notiz:\n\(rawText)"
    }
}

/// Tolerant gegenüber Code-Fences, Vor-/Nachtext und beiden Schlüsselnamen
/// (`details`/`description`). Zusätzliche Schlüssel (z. B. ein altes
/// `priority`) werden ignoriert. Wirft sichtbare Fehler – nie stilles Schlucken.
enum EnrichmentResponseParser {
    private struct Raw: Decodable {
        let title: String?
        let details: String?
        let description: String?
    }

    /// Schält das erste vollständige JSON-Objekt aus einem String.
    static func extractJSONObject(from raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            // ```json ... ``` entfernen
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let fence = text.range(of: "```", options: .backwards) {
                text = String(text[..<fence.lowerBound])
            }
        }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        return String(text[start...end])
    }

    static func parse(_ raw: String) throws -> EnrichmentSuggestion {
        guard let json = extractJSONObject(from: raw),
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
        return EnrichmentSuggestion(
            title: title,
            details: Self.nonEmpty(decoded.details ?? decoded.description)
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
