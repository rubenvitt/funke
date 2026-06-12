import Foundation

/// Konkreter Client gegen die ClickUp-REST-API v2.
///
/// - Base-URL `https://api.clickup.com/api/v2`.
/// - Authentisierung über das im `SecretStoring` hinterlegte Personal Token.
///   Der Header lautet bewusst `Authorization: <token>` (KEIN „Bearer").
/// - Keine Force-Unwraps an Netzgrenzen, kein stilles Verschlucken von Fehlern:
///   Jeder Pfad endet in einem typisierten `ClickUpError`.
struct ClickUpClient: ClickUpClienting {
    private let secrets: SecretStoring
    private let session: URLSession
    private let baseURL = URL(string: "https://api.clickup.com/api/v2")

    init(secrets: SecretStoring, session: URLSession = .shared) {
        self.secrets = secrets
        self.session = session
    }

    // MARK: - Protokoll

    func authorizedUser() async throws -> ClickUpUser {
        let dto: UserEnvelopeDTO = try await get(path: "/user")
        return ClickUpUser(id: dto.user.id, username: dto.user.username)
    }

    func teams() async throws -> [ClickUpTeam] {
        let dto: TeamsEnvelopeDTO = try await get(path: "/team")
        return dto.teams.map { ClickUpTeam(id: $0.id, name: $0.name) }
    }

    func spaces(teamID: String) async throws -> [ClickUpSpace] {
        let dto: SpacesEnvelopeDTO = try await get(
            path: "/team/\(teamID)/space",
            queryItems: [URLQueryItem(name: "archived", value: "false")]
        )
        return dto.spaces.map { ClickUpSpace(id: $0.id, name: $0.name) }
    }

    func folders(spaceID: String) async throws -> [ClickUpFolder] {
        let dto: FoldersEnvelopeDTO = try await get(
            path: "/space/\(spaceID)/folder",
            queryItems: [URLQueryItem(name: "archived", value: "false")]
        )
        return dto.folders.map { ClickUpFolder(id: $0.id, name: $0.name) }
    }

    func folderlessLists(spaceID: String) async throws -> [ClickUpList] {
        let dto: ListsEnvelopeDTO = try await get(
            path: "/space/\(spaceID)/list",
            queryItems: [URLQueryItem(name: "archived", value: "false")]
        )
        return dto.lists.map { ClickUpList(id: $0.id, name: $0.name) }
    }

    func folderLists(folderID: String) async throws -> [ClickUpList] {
        let dto: ListsEnvelopeDTO = try await get(
            path: "/folder/\(folderID)/list",
            queryItems: [URLQueryItem(name: "archived", value: "false")]
        )
        return dto.lists.map { ClickUpList(id: $0.id, name: $0.name) }
    }

    func createTask(
        listID: String,
        name: String,
        markdownDescription: String?,
        priority: Priority?,
        tags: [String]
    ) async throws {
        let body = CreateTaskBody(
            name: name,
            markdown_content: markdownDescription,
            priority: priority?.clickUpValue,
            tags: tags
        )
        try await send(path: "/list/\(listID)/task", method: "POST", body: body)
    }

    func todayTasks(teamID: String, assigneeID: Int, now: Date) async throws -> [TodayTask] {
        let calendar = Calendar.current
        // Alles bis zum Beginn des morgigen Tages gilt als „heute fällig oder überfällig".
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        let dueDateLtMs = Int(startOfTomorrow.timeIntervalSince1970 * 1000)

        let items = [
            URLQueryItem(name: "assignees[]", value: String(assigneeID)),
            URLQueryItem(name: "due_date_lt", value: String(dueDateLtMs)),
            URLQueryItem(name: "include_closed", value: "false"),
            URLQueryItem(name: "order_by", value: "due_date"),
            URLQueryItem(name: "subtasks", value: "false")
        ]
        let dto: TasksEnvelopeDTO = try await get(path: "/team/\(teamID)/task", queryItems: items)
        return dto.tasks.map { Self.makeTodayTask(from: $0) }
    }

    func listStatuses(listID: String) async throws -> [ClickUpStatusInfo] {
        let dto: ListDTO = try await get(path: "/list/\(listID)")
        return dto.statuses.map { ClickUpStatusInfo(name: $0.status, type: $0.type) }
    }

    func setStatus(taskID: String, status: String) async throws {
        try await send(path: "/task/\(taskID)", method: "PUT", body: SetStatusBody(status: status))
    }

    // MARK: - Mapping

    private static func makeTodayTask(from dto: TaskDTO) -> TodayTask {
        let dueDate: Date? = dto.due_date
            .flatMap { Double($0) }
            .map { Date(timeIntervalSince1970: $0 / 1000) }

        let priority: Priority? = {
            guard let prio = dto.priority else { return nil }
            if let label = prio.priority, let mapped = Priority(aiLabel: label) {
                return mapped
            }
            if let idString = prio.id, let intValue = Int(idString) {
                return Priority(clickUpValue: intValue)
            }
            return nil
        }()

        return TodayTask(
            id: dto.id,
            name: dto.name,
            priority: priority,
            dueDate: dueDate,
            statusName: dto.status?.status ?? "",
            statusType: dto.status?.type ?? "",
            listID: dto.list?.id,
            listName: dto.list?.name,
            url: dto.url
        )
    }

    // MARK: - Transport

    /// GET-Request, der einen `Decodable`-Wert zurückliefert.
    private func get<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: "GET", queryItems: queryItems)
        let data = try await perform(request)
        return try decode(Response.self, from: data)
    }

    /// Request mit JSON-Body ohne erwartete Antwort (POST/PUT).
    private func send<Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws {
        var request = try makeRequest(path: path, method: method, queryItems: nil)
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw ClickUpError.decoding("Anfrage konnte nicht kodiert werden: \(error.localizedDescription)")
        }
        _ = try await perform(request)
    }

    private func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem]?
    ) throws -> URLRequest {
        guard let token = secrets.string(for: .clickUpToken),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClickUpError.missingToken
        }
        guard let baseURL,
              var components = URLComponents(
                url: baseURL.appendingPathComponent(path),
                resolvingAgainstBaseURL: false
              ) else {
            throw ClickUpError.invalidURL
        }
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw ClickUpError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Führt den Request aus, prüft den HTTP-Status und liefert die rohen Daten.
    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw ClickUpError.transport(error.localizedDescription)
        } catch {
            throw ClickUpError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClickUpError.transport("Keine HTTP-Antwort erhalten.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClickUpError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return data
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ClickUpError.decoding(error.localizedDescription)
        }
    }

    /// Versucht, aus einem Fehlerkörper `{"err":...}` die Meldung zu lesen.
    private static func errorMessage(from data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(ErrorBodyDTO.self, from: data),
              let err = body.err,
              !err.isEmpty else {
            return nil
        }
        return err
    }
}

// MARK: - Wire-DTOs (privat, beschreiben ausschließlich das JSON-Format)

private struct UserEnvelopeDTO: Decodable {
    let user: UserDTO
    struct UserDTO: Decodable {
        let id: Int
        let username: String?
    }
}

private struct TeamsEnvelopeDTO: Decodable {
    let teams: [NamedIDDTO]
}

private struct SpacesEnvelopeDTO: Decodable {
    let spaces: [NamedIDDTO]
}

private struct FoldersEnvelopeDTO: Decodable {
    let folders: [NamedIDDTO]
}

private struct ListsEnvelopeDTO: Decodable {
    let lists: [NamedIDDTO]
}

/// Gemeinsame `{id,name}`-Form für Teams/Spaces/Folders/Lists.
private struct NamedIDDTO: Decodable {
    let id: String
    let name: String
}

private struct ListDTO: Decodable {
    let statuses: [StatusDTO]
    struct StatusDTO: Decodable {
        let status: String
        let type: String
    }
}

private struct TasksEnvelopeDTO: Decodable {
    let tasks: [TaskDTO]
}

private struct TaskDTO: Decodable {
    let id: String
    let name: String
    let url: String?
    let status: TaskStatusDTO?
    /// ms als String oder null.
    let due_date: String?
    /// Objekt `{priority:String?, id:String?}` oder null.
    let priority: TaskPriorityDTO?
    let list: TaskListDTO?

    struct TaskStatusDTO: Decodable {
        let status: String
        let type: String
    }

    struct TaskPriorityDTO: Decodable {
        let priority: String?
        let id: String?
    }

    struct TaskListDTO: Decodable {
        let id: String
        let name: String
    }
}

private struct ErrorBodyDTO: Decodable {
    let err: String?
}

// MARK: - Request-Bodies (privat)

/// Body für `POST /list/{list_id}/task`.
///
/// `markdown_content` und `priority` sind optional: Bei `nil` werden die Keys
/// dank synthetisiertem `encodeIfPresent` automatisch ausgelassen. Das
/// Markdown-Feld heißt bewusst `markdown_content` (NICHT `markdown_description`).
private struct CreateTaskBody: Encodable {
    let name: String
    let markdown_content: String?
    let priority: Int?
    let tags: [String]
}

/// Body für `PUT /task/{task_id}`.
private struct SetStatusBody: Encodable {
    let status: String
}
