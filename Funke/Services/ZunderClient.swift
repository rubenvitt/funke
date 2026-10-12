import Foundation

/// Konkreter Client gegen Zunder.
///
/// - Basis-URL aus den Einstellungen (z. B. `https://zunder.rubeen.dev`), bei
///   jedem Aufruf frisch gelesen.
/// - Authentisierung: `Authorization: Bearer zt_…` (API-Token aus dem Keychain).
///   Bearer-Anfragen brauchen keinen CSRF-Header.
/// - Schreiben über `POST /api/sync/push` (Feld-Operationen mit HLC),
///   Lesen der Heute-Liste über das MCP-Werkzeug `filter_tasks` (zustandslos,
///   ohne `initialize`).
/// - Keine Force-Unwraps an Netzgrenzen, kein stilles Verschlucken von Fehlern:
///   Jeder Pfad endet in einem typisierten `ZunderError`.
struct ZunderClient: ZunderClienting {
    /// Offene Status für die Heute-Liste (ohne `review`: nur in Dev-Projekten
    /// und dort eher Wartezustand als Tagesaufgabe).
    static let openStatuses = ["open", "in_progress", "blocked"]
    /// Obergrenze der Heute-Liste (Server erlaubt höchstens 500).
    static let todayLimit = 200
    static let mcpProtocolVersion = "2025-06-18"

    private let secrets: SecretStoring
    private let baseURL: @Sendable () -> String?
    private let session: URLSession
    private let factory: ZunderOpFactory
    private let calendar: Calendar

    init(
        secrets: SecretStoring,
        baseURL: @escaping @Sendable () -> String?,
        factory: ZunderOpFactory,
        session: URLSession = .shared,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.secrets = secrets
        self.baseURL = baseURL
        self.factory = factory
        self.session = session
        self.calendar = calendar
    }

    // MARK: - Protokoll

    func currentUser() async throws -> ZunderUser {
        let request = try makeRequest(path: ["api", "me"], method: "GET")
        let (data, _) = try await perform(request)
        let dto = try decode(MeDTO.self, from: data)
        return ZunderUser(name: dto.name, email: dto.email)
    }

    func createTask(_ draft: ZunderTaskDraft) async throws {
        try await push(draft.ops)
    }

    func completeTask(id: String, notBefore: Date?) async throws {
        let op = factory.makeStatusOp(taskID: id, status: "done", notBefore: notBefore)
        try await push([op])
    }

    func todayTasks(now: Date) async throws -> [TodayTask] {
        let arguments = FilterArguments(
            due_before: Self.dayString(now, calendar: calendar),
            status: Self.openStatuses,
            order_by: "due",
            limit: Self.todayLimit
        )
        let rpc = MCPRequest(
            id: 1,
            params: .init(name: "filter_tasks", arguments: arguments)
        )
        var request = try makeRequest(path: ["mcp"], method: "POST")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(Self.mcpProtocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        request.httpBody = try encode(rpc)

        let (raw, response) = try await perform(request)
        let data = Self.jsonPayload(from: raw, contentType: response.value(forHTTPHeaderField: "Content-Type"))

        // 1. Kopf prüfen: JSON-RPC-Fehler bzw. Werkzeugfehler (`isError`).
        let head = try decode(MCPHeadDTO.self, from: data)
        if let error = head.error {
            let message = error.message ?? "unbekannter Fehler"
            throw ZunderError.rejected("MCP-Fehler \(error.code.map(String.init) ?? "?"): \(message)")
        }
        guard let result = head.result else {
            throw ZunderError.decoding("MCP-Antwort ohne Ergebnis.")
        }
        if result.isError == true {
            let text = result.content?.first(where: { $0.text?.isEmpty == false })?.text
            throw ZunderError.rejected(text ?? "Werkzeugfehler ohne Meldung.")
        }

        // 2. Nutzlast lesen.
        let body = try decode(MCPFilterDTO.self, from: data)
        let base = try currentBaseURL()
        return body.result.structuredContent.tasks.map { makeTodayTask(from: $0, base: base) }
    }

    // MARK: - Push

    /// Sendet Operationen und prüft, dass jede angenommen wurde.
    private func push(_ ops: [ZunderOp]) async throws {
        var request = try makeRequest(path: ["api", "sync", "push"], method: "POST")
        request.httpBody = try encode(PushBody(client_id: factory.node, ops: ops))

        let (data, _) = try await perform(request)
        let result = try decode(ZunderPushResultDTO.self, from: data)

        if !result.rejected.isEmpty {
            throw ZunderError.rejected(Self.rejectionMessage(result.rejected))
        }
        let accepted = Set(result.accepted.map { $0.lowercased() })
        let missing = ops.filter { !accepted.contains($0.opID.lowercased()) }
        guard missing.isEmpty else {
            throw ZunderError.decoding("Server hat \(missing.count) Operation(en) weder angenommen noch abgelehnt.")
        }
    }

    /// Wählt die aussagekräftigste Ablehnung: `entity_rejected` ist nur die
    /// Folge einer anderen Ablehnung derselben Aufgabe.
    static func rejectionMessage(_ rejections: [ZunderPushResultDTO.RejectionDTO]) -> String {
        let primary = rejections.first { $0.code != "entity_rejected" && !($0.message ?? "").isEmpty }
            ?? rejections.first { !($0.message ?? "").isEmpty }
        if let message = primary?.message {
            return message
        }
        let code = rejections.first?.code ?? "unbekannt"
        return "Operation abgelehnt (\(code))."
    }

    // MARK: - Mapping

    private func makeTodayTask(from dto: TaskDTO, base: URL) -> TodayTask {
        TodayTask(
            id: dto.id,
            title: dto.title,
            status: dto.status,
            due: dto.due.flatMap { ZunderDue.parse($0, calendar: calendar) },
            locationName: Self.locationName(dto.location),
            updatedAt: dto.updated_at.flatMap(ZunderTimestamp.parse),
            webURL: Self.webURL(base: base, taskID: dto.id)
        )
    }

    static func locationName(_ location: ZunderLocationDTO?) -> String {
        guard let location else { return "Inbox" }
        let name = location.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch location.kind {
        case "inbox":
            return "Inbox"
        case "loose":
            return "Lose"
        case "area":
            return (name?.isEmpty == false ? name : nil) ?? "Bereich"
        case "project":
            guard let name, !name.isEmpty else { return "Projekt" }
            if let area = location.area_name?.trimmingCharacters(in: .whitespacesAndNewlines), !area.isEmpty {
                return "\(area) › \(name)"
            }
            return name
        default:
            return location.kind
        }
    }

    /// Link auf die Aufgabe in der Zunder-Web-UI (Hash-Route `#/aufgabe/<id>`).
    static func webURL(base: URL, taskID: String) -> URL? {
        URL(string: base.absoluteString + "/#/aufgabe/" + taskID)
    }

    /// Lokaler Kalendertag als `YYYY-MM-DD`.
    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 1970
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    /// Normalisiert die eingetragene Server-URL (ohne abschließenden Schrägstrich).
    static func normalizedBaseURL(_ raw: String?) throws -> URL {
        var text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ZunderError.notConfigured("keine Server-URL hinterlegt")
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else {
            throw ZunderError.invalidURL
        }
        return url
    }

    /// MCP darf als JSON oder (theoretisch) als SSE antworten. Bei SSE wird das
    /// letzte `data:`-Ereignis als JSON-Nutzlast genommen.
    static func jsonPayload(from data: Data, contentType: String?) -> Data {
        guard let contentType, contentType.lowercased().contains("text/event-stream"),
              let text = String(data: data, encoding: .utf8) else {
            return data
        }
        var events: [String] = []
        var current: [String] = []
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("data:") {
                current.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else if line.isEmpty, !current.isEmpty {
                events.append(current.joined(separator: "\n"))
                current = []
            }
        }
        if !current.isEmpty { events.append(current.joined(separator: "\n")) }
        guard let last = events.last else { return data }
        return Data(last.utf8)
    }

    // MARK: - Transport

    private func currentBaseURL() throws -> URL {
        try Self.normalizedBaseURL(baseURL())
    }

    private func makeRequest(path: [String], method: String) throws -> URLRequest {
        let base = try currentBaseURL()
        guard let token = secrets.string(for: .zunderToken)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw ZunderError.missingToken
        }
        let url = path.reduce(base) { $0.appendingPathComponent($1) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Führt den Request aus, prüft den HTTP-Status und liefert Daten + Antwort.
    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ZunderError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ZunderError.transport("Keine HTTP-Antwort erhalten.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ZunderError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return (data, http)
    }

    /// Deterministische Kodierung (sortierte Schlüssel): dieselben Operationen
    /// ergeben beim Nachsenden denselben Body.
    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(value)
        } catch {
            throw ZunderError.decoding("Anfrage konnte nicht kodiert werden: \(error.localizedDescription)")
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ZunderError.decoding(error.localizedDescription)
        }
    }

    /// Liest `{"error":{"message":…}}` aus einem Fehlerkörper. Die Meldung ist
    /// nur Zusatzinfo zum HTTP-Status – ein unlesbarer Körper ergibt `nil`.
    private static func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let body: ErrorBodyDTO
        do {
            body = try JSONDecoder().decode(ErrorBodyDTO.self, from: data)
        } catch {
            return nil
        }
        guard let message = body.error?.message, !message.isEmpty else { return nil }
        return message
    }
}

// MARK: - Wire-DTOs (beschreiben ausschließlich das JSON-Format)

private struct MeDTO: Decodable {
    let name: String?
    let email: String?
}

private struct ErrorBodyDTO: Decodable {
    struct Inner: Decodable {
        let code: String?
        let message: String?
    }
    let error: Inner?
}

private struct PushBody: Encodable {
    let client_id: String
    let ops: [ZunderOp]
}

struct ZunderPushResultDTO: Decodable {
    struct RejectionDTO: Decodable {
        let op_id: String?
        let code: String?
        let message: String?
    }
    let accepted: [String]
    let rejected: [RejectionDTO]
}

private struct FilterArguments: Encodable {
    let due_before: String
    let status: [String]
    let order_by: String
    let limit: Int
}

private struct MCPRequest: Encodable {
    struct Params: Encodable {
        let name: String
        let arguments: FilterArguments
    }
    let jsonrpc = "2.0"
    let id: Int
    let method = "tools/call"
    let params: Params
}

private struct MCPHeadDTO: Decodable {
    struct RPCError: Decodable {
        let code: Int?
        let message: String?
    }
    struct Result: Decodable {
        struct Content: Decodable {
            let type: String?
            let text: String?
        }
        let isError: Bool?
        let content: [Content]?
    }
    let result: Result?
    let error: RPCError?
}

private struct MCPFilterDTO: Decodable {
    struct Result: Decodable {
        let structuredContent: FilterResult
    }
    struct FilterResult: Decodable {
        let tasks: [TaskDTO]
        let total: Int?
        let truncated: Bool?
    }
    let result: Result
}

private struct TaskDTO: Decodable {
    let id: String
    let title: String
    let status: String
    let due: String?
    let location: ZunderLocationDTO?
    let updated_at: String?
}

struct ZunderLocationDTO: Decodable {
    let kind: String
    let name: String?
    let area_name: String?
}
