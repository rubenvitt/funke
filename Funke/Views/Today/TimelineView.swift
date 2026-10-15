import SwiftUI

/// Tages-Timeline im Glut-Look: links eine Stunden-Gutter, daneben zwei Spuren —
/// eine schmale Kalender-Spur (read-only Termine des gewählten Kalenders) und eine
/// breite Aufgaben-Spur mit Fokus-Blöcken.
///
/// Verschieben läuft über **Standard-Komponenten**: Tippt man auf den Text eines
/// Blocks, öffnet ein `Menu` mit freien Zeit-Slots (kein Drag-and-Drop, keine custom
/// Geste → kein Konflikt mit der umgebenden ScrollView). Die Checkbox bleibt ein
/// eigener Tap zum Abhaken.
struct TimelineView: View {
    let events: [CalendarEvent]
    /// Nur Aufgaben MIT `startDate` heute.
    let tasks: [TodayTask]
    let isDone: (TodayTask) -> Bool
    let onToggle: (TodayTask) -> Void
    /// Neue Startzeit für die Aufgabe mit dieser ID (Slot aus dem Menü).
    let onReschedule: (String, Date) -> Void
    /// Freie Slot-Vorschläge für eine Aufgabe (vom ViewModel berechnet).
    let suggestedSlots: (TodayTask) -> [Date]
    let now: Date

    // Fester Stundenbereich der Timeline.
    private let h0 = 8
    private let h1 = 19
    /// Punkte pro Minute — bestimmt die Gesamthöhe.
    private let ppm: CGFloat = 1.0

    // Spaltenmaße.
    private let gutterW: CGFloat = 34
    private let calW: CGFloat = 88
    private let gap: CGFloat = 8

    private var totalHeight: CGFloat { CGFloat((h1 - h0) * 60) * ppm }
    private var taskInset: CGFloat { gutterW + calW + gap }

    var body: some View {
        ZStack(alignment: .topLeading) {
            grid
            nowLine

            // Kalender-Spur — feste Spalte via HStack, nur vertikaler Offset.
            ForEach(visibleEvents) { item in
                HStack(spacing: 0) {
                    Color.clear.frame(width: gutterW)
                    calendarCard(item.event).frame(width: calW)
                    Spacer(minLength: 0)
                }
                .frame(height: item.height)
                .offset(y: item.top)
            }

            // Aufgaben-Spur — füllt die Restbreite, nur vertikaler Offset.
            ForEach(visibleTasks) { item in
                HStack(spacing: 0) {
                    Color.clear.frame(width: taskInset)
                    taskCard(item.task)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: item.height)
                .offset(y: item.top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: totalHeight, alignment: .topLeading)
        .clipped()
    }

    // MARK: - Raster & Now-Linie

    private var grid: some View {
        ForEach(h0...h1, id: \.self) { hour in
            HStack(spacing: 0) {
                Text(String(format: "%02d", hour))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FunkeTheme.dim)
                    .frame(width: gutterW, alignment: .leading)
                Rectangle()
                    .fill(FunkeTheme.line2)
                    .frame(height: 1)
            }
            .offset(y: y(forMinutes: hour * 60))
        }
    }

    @ViewBuilder
    private var nowLine: some View {
        let nowMin = minutes(now)
        if nowMin >= h0 * 60 && nowMin <= h1 * 60 {
            HStack(spacing: 0) {
                Color.clear.frame(width: gutterW)
                Rectangle().fill(FunkeTheme.red).frame(height: 2)
            }
            .overlay(alignment: .leading) {
                Circle()
                    .fill(FunkeTheme.red)
                    .frame(width: 7, height: 7)
                    .offset(x: gutterW - 3.5)
            }
            .offset(y: y(forMinutes: nowMin))
            .zIndex(2)
        }
    }

    // MARK: - Karten

    private func calendarCard(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FunkeTheme.text)
                .lineLimit(2)
            Text("\(Self.hm.string(from: event.start))–\(Self.hm.string(from: event.end))")
                .font(.system(size: 10))
                .foregroundStyle(FunkeTheme.dim)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FunkeTheme.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5).fill(FunkeTheme.dim.opacity(0.55)).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func taskCard(_ task: TodayTask) -> some View {
        let done = isDone(task)
        // Akzent-Fläche nur für Flamme/Feuer; Funke und ohne Art bleiben „surface".
        let focus = task.art == .flamme || task.art == .feuer
        let fill = focus ? FunkeTheme.accentSoft : FunkeTheme.surface
        let border = focus ? FunkeTheme.accentLine : FunkeTheme.line2
        let endDate = (task.startDate ?? now).addingTimeInterval(TimeInterval(task.durationMinutes * 60))

        return HStack(alignment: .top, spacing: 8) {
            Button {
                onToggle(task)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(done ? FunkeTheme.positive : FunkeTheme.dim)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(task.name) erledigen")

            // Tap auf den Text öffnet das Verschieben-Menü.
            Menu {
                rescheduleMenu(for: task)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FunkeTheme.text)
                        .strikethrough(done)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let label = task.art?.focusLabel {
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FunkeTheme.accent)
                            .lineLimit(1)
                    }
                    Text("\(Self.hm.string(from: task.startDate ?? now))–\(Self.hm.string(from: endDate))")
                        .font(.system(size: 10))
                        .foregroundStyle(FunkeTheme.dim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            if focus {
                Rectangle().fill(FunkeTheme.accent).frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(done ? 0.5 : 1)
    }

    /// Menü-Inhalt zum Verschieben: freie Slots als Buttons.
    @ViewBuilder
    private func rescheduleMenu(for task: TodayTask) -> some View {
        let slots = suggestedSlots(task)
        if slots.isEmpty {
            Text("Kein freier Slot heute")
        } else {
            Section("Verschieben auf") {
                ForEach(slots, id: \.self) { slot in
                    Button(slot.formatted(date: .omitted, time: .shortened)) {
                        onReschedule(task.id, slot)
                    }
                }
            }
        }
    }

    // MARK: - Sichtbare, auf das Zeitfenster geklemmte Elemente

    private struct PositionedEvent: Identifiable {
        let id: String
        let event: CalendarEvent
        let top: CGFloat
        let height: CGFloat
    }

    private struct PositionedTask: Identifiable {
        let id: String
        let task: TodayTask
        let top: CGFloat
        let height: CGFloat
    }

    /// Termine, die das 8–19-Uhr-Fenster schneiden — Position/Höhe darauf geklemmt.
    private var visibleEvents: [PositionedEvent] {
        events.compactMap { event in
            let s = max(minutes(event.start), h0 * 60)
            let e = min(eventEndMinutes(event), h1 * 60)
            guard e > s else { return nil }
            return PositionedEvent(id: event.id, event: event, top: y(forMinutes: s), height: max(28, CGFloat(e - s) * ppm))
        }
    }

    /// Aufgaben, deren Startzeit ins Fenster geklemmt wird.
    private var visibleTasks: [PositionedTask] {
        tasks.map { task in
            let raw = minutes(task.startDate ?? now)
            let start = min(max(raw, h0 * 60), h1 * 60 - 15)
            return PositionedTask(
                id: task.id, task: task,
                top: y(forMinutes: start), height: height(forMinutes: task.durationMinutes)
            )
        }
    }

    // MARK: - Geometrie-Helfer

    /// Y-Position (in Punkten) für eine Minute seit Mitternacht.
    private func y(forMinutes minutesSinceMidnight: Int) -> CGFloat {
        CGFloat(minutesSinceMidnight - h0 * 60) * ppm
    }

    /// Kartenhöhe für eine Dauer in Minuten (mind. 34 pt).
    private func height(forMinutes durationMin: Int) -> CGFloat {
        max(34, CGFloat(durationMin) * ppm)
    }

    private func eventEndMinutes(_ event: CalendarEvent) -> Int {
        max(minutes(event.start) + 15, minutes(event.end))
    }

    /// Minuten seit Mitternacht für ein Datum.
    private func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()
}
