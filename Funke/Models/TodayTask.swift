import Foundation

/// Eine heute fällige oder überfällige, offene Aufgabe aus Zunder,
/// aufbereitet für die Heute-Liste.
struct TodayTask: Identifiable, Equatable, Sendable, Hashable {
    let id: String
    let title: String
    /// Zunder-Statuscode: open | in_progress | blocked (andere werden nicht geladen).
    let status: String
    let due: ZunderDue?
    /// Anzeigename der wirksamen Stelle (Inbox, Lose, Bereich oder Projekt).
    let locationName: String
    /// Letzte Änderung laut Server; hebt den HLC beim Abhaken darüber.
    let updatedAt: Date?
    /// Link in die Zunder-Web-UI (`<Server>/#/aufgabe/<id>`).
    let webURL: URL?

    init(
        id: String,
        title: String,
        status: String,
        due: ZunderDue?,
        locationName: String,
        updatedAt: Date? = nil,
        webURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.due = due
        self.locationName = locationName
        self.updatedAt = updatedAt
        self.webURL = webURL
    }

    var dueDate: Date? { due?.date }

    /// Deutscher Anzeigename des Status (nur für nicht-„offen" sichtbar).
    var statusLabel: String? {
        switch status {
        case "in_progress": return "In Arbeit"
        case "blocked": return "Blockiert"
        case "review": return "Review"
        default: return nil
        }
    }

    /// True, wenn die Fälligkeit vor dem heutigen Tagesbeginn liegt
    /// (Zunder vergleicht Fälligkeiten nach Kalendertag).
    func isOverdue(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let dueDate else { return false }
        return dueDate < calendar.startOfDay(for: referenceDate)
    }
}
