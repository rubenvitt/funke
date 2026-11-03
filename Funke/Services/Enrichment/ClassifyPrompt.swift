import Foundation

/// Geteilter Prompt + Schema + toleranter Parser für die kombinierte
/// Klassifikation (Task vs. Notiz) **und** Veredelung. Spiegelt `EnrichmentPrompt`,
/// liefert aber zusätzlich das Feld `kind`. Anthropic/OpenRouter nutzen denselben
/// System-Prompt; die Apple-Provider nutzen ihn als `instructions`.
enum ClassifyPrompt {
    static let systemInstruction = """
    Entscheide, ob die folgende kurze Eingabe eine umsetzbare AUFGABE (task) oder \
    eine reine NOTIZ/Information (note) ist.
    - task: enthält eine Handlung/ein To-do (oft mit Verb), etwas zu erledigen.
    - note: ein Gedanke, eine Information, ein Konzept ohne konkrete Handlung.
    Veredele die Eingabe zu einem knappen Titel und einem aufgeräumten Body \
    (korrigiere offensichtliche Tipp-/Erkennungsfehler, formatiere sinnvoll, \
    füge aber NICHTS hinzu und bewahre die Bedeutung).
    Bei einer Aufgabe: Steht am Ende der Eingabe eine Fälligkeit (z. B. heute, \
    morgen, übermorgen, ein Wochentag, ein Datum wie 14.10., auch mit bis/am davor), \
    ein #Ziel oder +woche, setze diese Wörter unverändert und klein geschrieben \
    ans Ende des Titels, ohne Satzzeichen danach.
    Antworte AUSSCHLIESSLICH als JSON-Objekt – ohne Erklärung, ohne Codeblock:
    {"kind":"task|note","title":"<knapp>","body":"<aufgeräumt>"}
    Antworte auf Deutsch, falls die Eingabe deutsch ist.
    """

    /// JSON-Schema-String für strukturierte Ausgaben (Anthropic / OpenRouter).
    static let jsonSchemaString = """
    {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "kind": { "type": "string", "enum": ["task", "note"] },
        "title": { "type": "string" },
        "body": { "type": "string" }
      },
      "required": ["kind", "title", "body"]
    }
    """

    static func userPrompt(for rawText: String) -> String {
        "Eingabe:\n\(rawText)"
    }
}

/// Tolerant gegenüber Code-Fences und Vor-/Nachtext. Fehlendes/unbekanntes `kind`
/// fällt konservativ auf `.note` zurück (lieber Notiz als irrtümliche Zunder-Aufgabe).
/// Zusätzliche Schlüssel (z. B. ein altes `priority`) werden ignoriert.
enum ClassifyResponseParser {
    private struct Raw: Decodable {
        let kind: String?
        let title: String?
        let body: String?
        let details: String?
    }

    static func parse(_ raw: String) throws -> CaptureClassification {
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

        let kind = CaptureKind(rawValue: (decoded.kind ?? "").lowercased()) ?? .note
        let bodyRaw = (decoded.body ?? decoded.details ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = bodyRaw.isEmpty ? title : bodyRaw
        return CaptureClassification(kind: kind, title: title, body: body)
    }
}
