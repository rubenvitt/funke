import Foundation

/// Eine heute fällige oder überfällige Aufgabe aus ClickUp,
/// aufbereitet für die Heute-Liste.
struct TodayTask: Identifiable, Equatable, Sendable, Hashable {
    let id: String
    let name: String
    let priority: Priority?
    let dueDate: Date?
    /// Name des aktuellen Status (z. B. "to do").
    let statusName: String
    /// ClickUp-Statustyp: open | custom | closed | done.
    let statusType: String
    /// Liste, zu der die Aufgabe gehört – nötig, um den korrekten
    /// Erledigt-Status dynamisch zu ermitteln.
    let listID: String?
    let listName: String?
    let url: String?
    /// Geplanter Start (ClickUp `start_date`) — Position auf der Timeline.
    let startDate: Date?
    /// Geschätzte Dauer in Millisekunden (ClickUp `time_estimate`).
    let timeEstimateMs: Int?
    /// Phönix-„Art" (Flamme/Funke/…) aus dem Custom-Field „🗓️ Art".
    let art: PhoenixArt?

    init(
        id: String,
        name: String,
        priority: Priority?,
        dueDate: Date?,
        statusName: String,
        statusType: String,
        listID: String?,
        listName: String?,
        url: String?,
        startDate: Date? = nil,
        timeEstimateMs: Int? = nil,
        art: PhoenixArt? = nil
    ) {
        self.id = id
        self.name = name
        self.priority = priority
        self.dueDate = dueDate
        self.statusName = statusName
        self.statusType = statusType
        self.listID = listID
        self.listName = listName
        self.url = url
        self.startDate = startDate
        self.timeEstimateMs = timeEstimateMs
        self.art = art
    }

    /// Effektive Dauer in Minuten: aus `time_estimate`, sonst aus der Phönix-Art,
    /// sonst 60 min als neutraler Fallback.
    var durationMinutes: Int {
        if let timeEstimateMs, timeEstimateMs > 0 {
            return max(15, timeEstimateMs / 60_000)
        }
        return art?.defaultDurationMinutes ?? 60
    }

    /// True, wenn die Fälligkeit vor dem heutigen Tagesbeginn liegt.
    func isOverdue(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let dueDate else { return false }
        return dueDate < calendar.startOfDay(for: referenceDate)
    }
}
