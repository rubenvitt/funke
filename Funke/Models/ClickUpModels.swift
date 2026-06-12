import Foundation

/// Der über den Token authentifizierte ClickUp-Nutzer.
/// `id` ist numerisch – genau das erwartet der `assignees[]`-Filter.
struct ClickUpUser: Equatable, Sendable {
    let id: Int
    let username: String?
}

/// Workspace (ClickUp nennt das in der API "team").
struct ClickUpTeam: Identifiable, Equatable, Sendable, Hashable {
    let id: String
    let name: String
}

struct ClickUpSpace: Identifiable, Equatable, Sendable, Hashable {
    let id: String
    let name: String
}

struct ClickUpFolder: Identifiable, Equatable, Sendable, Hashable {
    let id: String
    let name: String
}

struct ClickUpList: Identifiable, Equatable, Sendable, Hashable {
    let id: String
    let name: String
}

/// Ein erlaubter Status einer Liste, reduziert auf das Nötige.
struct ClickUpStatusInfo: Equatable, Sendable, Hashable {
    let name: String
    /// ClickUp-Statustyp: open | custom | closed | done.
    let type: String
}

extension Array where Element == ClickUpStatusInfo {
    /// Wählt den „Erledigt"-Status dynamisch: bevorzugt den terminalen
    /// `closed`-Status, sonst einen `done`-Status. ClickUp-Listen benennen
    /// ihre Status frei – deshalb wird hier nie ein Name hart angenommen.
    func doneStatus() -> ClickUpStatusInfo? {
        first { $0.type == "closed" } ?? first { $0.type == "done" }
    }
}
