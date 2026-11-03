import Foundation

/// Schickt Aufgaben zuerst ans Vault Cockpit (`POST <relayBaseURL>/tasks`, also
/// `<PUBLIC_URL>/funke/tasks`), damit dort die Schnelleingabe-Syntax greift:
/// `morgen.` am Ende wird zur Fälligkeit, `#gesundheit` zum Ziel, `+woche` zum
/// Phönix-Schritt (VCP-119). Alles andere (Heute-Liste, Abhaken, Verbindung
/// testen) geht unverändert an den inneren Zunder-Client.
///
/// Rückfall auf den direkten Weg an Zunder:
/// - kein Relay eingetragen,
/// - das Relay kennt `/tasks` nicht (404/405, z. B. der alte Funke-Relay),
/// - im Cockpit ist Zunder nicht eingerichtet (503).
///
/// Ein Netzfehler fällt **nicht** zurück, sondern wird als `ZunderError.transport`
/// geworfen: Der Router puffert den Entwurf, und das Nachsenden ans Cockpit mit
/// derselben Task-ID ist dort idempotent. Ein Rückfall an Zunder könnte eine
/// Aufgabe doppelt anlegen, falls die erste Anfrage doch angekommen war.
struct CockpitTaskClient: ZunderClienting {
    let inner: ZunderClienting
    /// Relay-URL und Token, bei jedem Aufruf frisch gelesen; `nil` = kein Relay.
    let relay: @Sendable () -> (baseURL: URL, token: String)?
    var session: URLSession = .shared

    func createTask(_ draft: ZunderTaskDraft) async throws {
        guard let relay = relay() else {
            return try await inner.createTask(draft)
        }

        let payload = Self.payload(for: draft)
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            return try await inner.createTask(draft)
        }

        var request = URLRequest(url: relay.baseURL.appendingPathComponent("tasks"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(relay.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ZunderError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ZunderError.decoding("Keine HTTP-Antwort vom Cockpit erhalten.")
        }

        switch http.statusCode {
        case 200...299:
            return
        case 404, 405, 503:
            try await inner.createTask(draft)
        case 400, 502:
            // Inhaltlich abgelehnt (vom Cockpit oder von Zunder dahinter).
            throw ZunderError.rejected(Self.message(from: data) ?? "HTTP \(http.statusCode)")
        default:
            throw ZunderError.http(status: http.statusCode, message: Self.message(from: data))
        }
    }

    func currentUser() async throws -> ZunderUser {
        try await inner.currentUser()
    }

    func todayTasks(now: Date) async throws -> [TodayTask] {
        try await inner.todayTasks(now: now)
    }

    func completeTask(id: String, notBefore: Date?) async throws {
        try await inner.completeTask(id: id, notBefore: notBefore)
    }

    /// `{id, title, description?}` aus den Operationen des Entwurfs. Titel und
    /// Beschreibung sind dort schon gekürzt bzw. ergänzt (`ZunderOpFactory`).
    static func payload(for draft: ZunderTaskDraft) -> [String: Any] {
        var payload: [String: Any] = ["id": draft.taskID]
        for op in draft.ops {
            guard case .string(let value) = op.value else { continue }
            switch op.field {
            case "title": payload["title"] = value
            case "description": payload["description"] = value
            default: break
            }
        }
        return payload
    }

    /// Liest `message` (fertiger Satz des Cockpits) oder `error` aus dem Fehlerkörper.
    private static func message(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = (object["message"] as? String) ?? (object["error"] as? String),
              !message.isEmpty else {
            return nil
        }
        return message
    }
}
