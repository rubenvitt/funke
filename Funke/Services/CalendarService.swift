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

/// Ein auswählbarer Kalender (für die Einstellung „Timeblocking-Kalender").
struct CalendarInfo: Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let title: String
}

/// Read-only-Zugriff auf den System-Kalender. Protokollbasiert, damit ViewModels
/// gegen Stubs testbar bleiben und macOS/watchOS leer liefern können.
protocol CalendarProviding: Sendable {
    /// Verfügbare Termin-Kalender (für die Auswahl). Leer, wenn kein Zugriff.
    func availableCalendars() async -> [CalendarInfo]
    /// Heutige Termine; auf `calendarID` eingeschränkt, falls gesetzt.
    func todayEvents(now: Date, calendarID: String?) async -> [CalendarEvent]
}

/// Lädt Kalender/Termine read-only über EventKit (nur iOS).
/// Kein Zugriff / Fehler / andere Plattform → `[]`. Crasht nie.
struct CalendarService: CalendarProviding {
    func availableCalendars() async -> [CalendarInfo] {
        #if os(iOS) && canImport(EventKit)
        let store = EKEventStore()
        guard await Self.requestAccess(store) else { return [] }
        return store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        #else
        return []
        #endif
    }

    /// Termine des heutigen Tages (Tagesbeginn…Beginn des Folgetags), nach
    /// Startzeit sortiert. Ist `calendarID` gesetzt, werden nur dessen Termine
    /// geladen — so zeigt die Timeline genau den gewählten Timeblocking-Kalender.
    func todayEvents(now: Date = Date(), calendarID: String? = nil) async -> [CalendarEvent] {
        #if os(iOS) && canImport(EventKit)
        let store = EKEventStore()
        guard await Self.requestAccess(store) else { return [] }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        // Auf den gewählten Kalender einschränken (falls noch vorhanden); sonst alle.
        let selected: [EKCalendar]? = calendarID.flatMap { id in
            store.calendars(for: .event).filter { $0.calendarIdentifier == id }
        }.flatMap { $0.isEmpty ? nil : $0 }

        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: selected)
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

    #if os(iOS) && canImport(EventKit)
    /// Fragt den Vollzugriff an (iOS 17+); bei Ablehnung/Fehler `false`.
    private static func requestAccess(_ store: EKEventStore) async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }
    #endif
}
