import Foundation
#if canImport(EventKit)
import EventKit
#endif

/// Ein Kalendertermin des heutigen Tages — schlanke, plattformneutrale Sicht
/// für die Tages-Timeline. Bewusst frei von EventKit-Typen, damit macOS/watchOS
/// problemlos kompilieren (dort liefert der Service schlicht `[]`).
struct CalendarEvent: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
}

/// Lädt die heutigen Kalendertermine read-only über EventKit (nur iOS).
/// Kein Zugriff / Fehler / andere Plattform → `[]`. Crasht nie.
struct CalendarService: Sendable {
    /// Termine des heutigen Tages (Tagesbeginn…Beginn des Folgetags), nach
    /// Startzeit sortiert. Fragt bei Bedarf den Vollzugriff an (iOS 17+).
    func todayEvents(now: Date = Date()) async -> [CalendarEvent] {
        #if os(iOS) && canImport(EventKit)
        let store = EKEventStore()
        // Zugriff anfragen — bei Ablehnung/Fehler einfach leer zurück.
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        guard granted else { return [] }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        return store.events(matching: predicate)
            // Ganztägige Termine würden die Timeline sprengen → ausblenden.
            .filter { !$0.isAllDay }
            .map { event in
                CalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Termin",
                    start: event.startDate,
                    end: event.endDate
                )
            }
            .sorted { $0.start < $1.start }
        #else
        return []
        #endif
    }
}
