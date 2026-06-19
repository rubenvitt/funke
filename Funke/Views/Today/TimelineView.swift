import SwiftUI

/// Tages-Timeline im Glut-Look: links eine Stunden-Gutter, daneben zwei Spuren —
/// eine schmale Kalender-Spur (read-only Termine) und eine breite Aufgaben-Spur
/// mit ziehbaren Fokus-Blöcken. Auf iOS lassen sich Aufgaben per Drag verschieben
/// (15-Minuten-Raster); auf anderen Plattformen ist die Ansicht rein darstellend.
struct TimelineView: View {
    let events: [CalendarEvent]
    /// Nur Aufgaben MIT `startDate` heute.
    let tasks: [TodayTask]
    let isDone: (TodayTask) -> Bool
    let onToggle: (TodayTask) -> Void
    let onReschedule: (TodayTask, Date) -> Void
    let now: Date

    // Fester Stundenbereich der Timeline.
    private let h0 = 8
    private let h1 = 19
    /// Punkte pro Minute — bestimmt die Gesamthöhe.
    private let ppm: CGFloat = 1.0

    // Spaltenmaße.
    private let gutterW: CGFloat = 30
    private let calW: CGFloat = 84
    private let gap: CGFloat = 8

    // Aktiver Drag (nur eine Karte gleichzeitig).
    @State private var draggingID: String?
    @State private var dragY: CGFloat = 0

    private var totalHeight: CGFloat { CGFloat((h1 - h0) * 60) * ppm }

    var body: some View {
        GeometryReader { geo in
            let taskX = gutterW + calW + gap
            let taskW = max(80, geo.size.width - taskX)

            ZStack(alignment: .topLeading) {
                grid(width: geo.size.width)

                // Kalender-Spur
                ForEach(events) { event in
                    calendarCard(event)
                        .frame(width: calW, height: height(forMinutes: durationMinutes(event)), alignment: .topLeading)
                        .offset(x: gutterW, y: max(0, y(forMinutes: minutes(event.start))))
                }

                // Aufgaben-Spur
                ForEach(tasks) { task in
                    let base = minutes(task.start ?? now)
                    let isDragging = draggingID == task.id
                    taskCard(task, baseMinutes: base)
                        .frame(width: taskW, height: height(forMinutes: task.durationMinutes), alignment: .topLeading)
                        .offset(x: taskX, y: max(0, y(forMinutes: base) + (isDragging ? dragY : 0)))
                        .shadow(color: .black.opacity(isDragging ? 0.18 : 0), radius: isDragging ? 10 : 0, x: 0, y: isDragging ? 6 : 0)
                        .zIndex(isDragging ? 1 : 0)
                }

                nowLine(width: geo.size.width)
            }
            .frame(width: geo.size.width, height: totalHeight, alignment: .topLeading)
        }
        .frame(height: totalHeight)
    }

    // MARK: - Raster & Now-Linie

    private func grid(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(h0...h1, id: \.self) { hour in
                let lineY = y(forMinutes: hour * 60)
                // Stunden-Trennlinie
                Rectangle()
                    .fill(FunkeTheme.line2)
                    .frame(width: max(0, width - gutterW), height: 1)
                    .offset(x: gutterW, y: lineY)
                // Stunden-Label in der Gutter
                Text(String(format: "%02d", hour))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FunkeTheme.dim)
                    .offset(x: 0, y: lineY - 6)
            }
        }
    }

    @ViewBuilder
    private func nowLine(width: CGFloat) -> some View {
        let nowMin = minutes(now)
        if nowMin >= h0 * 60 && nowMin <= h1 * 60 {
            let lineY = y(forMinutes: nowMin)
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(FunkeTheme.red)
                    .frame(width: 7, height: 7)
                    .offset(x: gutterW - 7, y: lineY - 3)
                Rectangle()
                    .fill(FunkeTheme.red)
                    .frame(width: max(0, width - gutterW), height: 2)
                    .offset(x: gutterW, y: lineY - 1)
            }
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FunkeTheme.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(FunkeTheme.dim.opacity(0.5)).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func taskCard(_ task: TodayTask, baseMinutes: Int) -> some View {
        let done = isDone(task)
        // Akzent-Fläche nur für Flamme/Feuer; Funke und ohne Art bleiben „surface".
        let focus = task.art == .flamme || task.art == .feuer
        let fill = focus ? FunkeTheme.accentSoft : FunkeTheme.surface
        let border = focus ? FunkeTheme.accentLine : FunkeTheme.line2
        let endDate = (task.start ?? now).addingTimeInterval(TimeInterval(task.durationMinutes * 60))

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

            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FunkeTheme.text)
                    .strikethrough(done)
                    .lineLimit(2)
                if let label = task.art?.focusLabel {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FunkeTheme.accent)
                }
                Text("\(Self.hm.string(from: task.start ?? now))–\(Self.hm.string(from: endDate))")
                    .font(.system(size: 10))
                    .foregroundStyle(FunkeTheme.dim)
            }
            // Ziehfläche nur über dem Textbereich — Checkbox-Tap löst keinen Drag aus.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            #if os(iOS)
            .gesture(drag(for: task, baseMinutes: baseMinutes))
            #endif

            Spacer(minLength: 0)
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

    // MARK: - Drag-Logik (iOS)

    // Verschieben erst nach kurzem Long-Press aktivieren — sonst „kämpft" der
    // vertikale Drag mit der vertikalen ScrollView von „Heute" (SwiftUI gäbe dem
    // Scrollen den Vorrang). Long-Press → Block hebt sich an → ziehen → loslassen.
    #if os(iOS)
    private func drag(for task: TodayTask, baseMinutes: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    // Long-Press erkannt → Karte zum Ziehen „freigeben".
                    draggingID = task.id
                    dragY = 0
                case .second(true, let drag):
                    draggingID = task.id
                    dragY = drag?.translation.height ?? 0
                default:
                    break
                }
            }
            .onEnded { value in
                defer { draggingID = nil; dragY = 0 }
                guard case .second(true, let drag?) = value else { return }

                let deltaMin = Int((drag.translation.height / ppm).rounded())
                let raw = baseMinutes + deltaMin
                // Auf 15-Minuten-Raster runden.
                let snapped = Int((Double(raw) / 15).rounded()) * 15
                // In [H0:00, H1:00 − Dauer] klemmen.
                let lo = h0 * 60
                let hi = max(lo, h1 * 60 - task.durationMinutes)
                let clamped = min(max(snapped, lo), hi)

                if clamped != baseMinutes {
                    let day = Calendar.current.startOfDay(for: task.start ?? now)
                    let newStart = Calendar.current.date(byAdding: .minute, value: clamped, to: day) ?? day
                    onReschedule(task, newStart)
                }
            }
    }
    #endif

    // MARK: - Geometrie-Helfer

    /// Y-Position (in Punkten) für eine Minute seit Mitternacht.
    private func y(forMinutes minutesSinceMidnight: Int) -> CGFloat {
        CGFloat(minutesSinceMidnight - h0 * 60) * ppm
    }

    /// Kartenhöhe für eine Dauer in Minuten (mind. 34 pt).
    private func height(forMinutes durationMin: Int) -> CGFloat {
        max(34, CGFloat(durationMin) * ppm)
    }

    private func durationMinutes(_ event: CalendarEvent) -> Int {
        max(15, Int(event.end.timeIntervalSince(event.start) / 60))
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

private extension TodayTask {
    /// Bequemer Alias — die Timeline arbeitet ausschließlich mit dem geplanten Start.
    var start: Date? { startDate }
}
