import Foundation

/// Schreibt Notizen über den Funke-Relay-Server (`POST <baseURL>/notes`).
/// Der Server (`obsidian-headless` + Mini-Endpoint) legt die Datei im Vault ab;
/// Obsidian Sync verteilt sie an alle Geräte. Kein App-Wechsel, kein Flow-Bruch.
///
/// Der Dateiname wird **client-seitig** über `NoteFileName` gebaut (DRY: die
/// Sanitizing-Logik lebt nur hier, der Server schreibt „dumm"). Bearer-Token
/// kommt aus dem Keychain und wird nie geloggt.
struct RelayNoteSink: NoteSink {
    let baseURL: URL
    let token: String
    let folder: String
    var session: URLSession = .shared
    var timeZone: TimeZone = .current

    func write(_ draft: NoteDraft) async throws {
        let filename = NoteFileName.make(title: draft.title, createdAt: draft.createdAt, timeZone: timeZone)
        let payload: [String: Any] = [
            "folder": folder,
            "filename": filename,
            "content": draft.body,
            "createdAt": ISO8601DateFormatter().string(from: draft.createdAt),
        ]

        let httpBody: Data
        do {
            httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw NoteSinkError.invalidResponse("Anfrage konnte nicht serialisiert werden: \(error.localizedDescription)")
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("notes"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Netzproblem → Aufrufer puffert (Offline-Queue).
            throw NoteSinkError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw NoteSinkError.invalidResponse("Keine HTTP-Antwort vom Relay-Server erhalten.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw NoteSinkError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
    }

    /// Liest `{"error":...}` oder `{"message":...}` aus dem Fehlerkörper; sonst `nil`.
    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = (object["error"] as? String) ?? (object["message"] as? String),
              !message.isEmpty else {
            return nil
        }
        return message
    }
}
