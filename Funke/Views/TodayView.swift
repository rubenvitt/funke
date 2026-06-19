import SwiftUI

/// „Heute" im Glut-Look: Execution-Ring im Kopf, Feuersturm-Chip, überfällige
/// Karten und eine ziehbare Tages-Timeline (Kalender + ClickUp-Fokusblöcke).
/// Nicht terminierte Aufgaben erscheinen darunter als einfache Karten.
struct TodayView: View {
    @ObservedObject var viewModel: TodayViewModel

    /// Heutige Kalendertermine — additiv, blockieren das Laden der Aufgaben nicht.
    @State private var events: [CalendarEvent] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
            }
            .background(FunkeTheme.background)
            .refreshable {
                await viewModel.load()
                events = await CalendarService().todayEvents()
            }
            .task { await viewModel.load() }
            .task { events = await CalendarService().todayEvents() }
        }
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if viewModel.isLoading && viewModel.tasks.isEmpty {
                loadingState
            } else if let error = viewModel.error {
                errorState(error)
            } else if viewModel.isEmpty {
                emptyState
            } else {
                if let info = viewModel.feuersturm {
                    feuersturmChip(info)
                }
                if !viewModel.overdue.isEmpty {
                    overdueSection
                }
                timelineSection
                unscheduledSection
            }
        }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Heute").funkeTitle()
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FunkeTheme.dim)
            }
            Spacer()
            VStack(spacing: 6) {
                ProgressRing(progress: viewModel.executionProgress)
                Text("EXECUTION")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(FunkeTheme.dim)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Feuersturm-Chip

    private func feuersturmChip(_ info: FeuersturmInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .foregroundStyle(FunkeTheme.accent)
            Text("\(info.title) · Woche \(info.weekIndex) von \(info.totalWeeks)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(FunkeTheme.text)
            Spacer(minLength: 8)
            Text("\(viewModel.plannedFlames) Flammen geplant")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FunkeTheme.dim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(FunkeTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(FunkeTheme.accentLine, lineWidth: 1)
        )
    }

    // MARK: - Überfällig

    private var overdueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(FunkeTheme.red).frame(width: 7, height: 7)
                Text("Überfällig · \(viewModel.overdue.count)")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(FunkeTheme.red)
            }
            ForEach(viewModel.overdue) { task in
                overdueCard(task)
            }
        }
    }

    private func overdueCard(_ task: TodayTask) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await viewModel.complete(task) }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(FunkeTheme.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(task.name) erledigen")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FunkeTheme.text)
                if let due = task.dueDate {
                    Text(Self.overdueText(due))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FunkeTheme.red)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FunkeTheme.redBg, in: RoundedRectangle(cornerRadius: FunkeTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FunkeTheme.cardRadius, style: .continuous)
                .strokeBorder(FunkeTheme.redLine, lineWidth: 1)
        )
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kalender").funkeSectionLabel()
                Spacer()
                Text("Fokus · ziehbar").funkeSectionLabel()
            }
            TimelineView(
                events: events,
                tasks: viewModel.scheduled.filter { $0.startDate != nil },
                isDone: viewModel.isDone,
                onToggle: { task in Task { await viewModel.complete(task) } },
                onReschedule: { task, date in Task { await viewModel.reschedule(task, to: date) } },
                now: Date()
            )
        }
    }

    // MARK: - Nicht eingeplant

    @ViewBuilder
    private var unscheduledSection: some View {
        let unscheduled = viewModel.scheduled.filter { $0.startDate == nil }
        if !unscheduled.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nicht eingeplant").funkeSectionLabel()
                ForEach(unscheduled) { task in
                    unscheduledCard(task)
                }
            }
        }
    }

    private func unscheduledCard(_ task: TodayTask) -> some View {
        let done = viewModel.isDone(task)
        return FunkeCard {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    Task { await viewModel.complete(task) }
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(done ? FunkeTheme.positive : FunkeTheme.dim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(task.name) erledigen")

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FunkeTheme.text)
                        .strikethrough(done)
                    if let label = task.art?.focusLabel {
                        Text(label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FunkeTheme.accent)
                    }
                }
                Spacer(minLength: 0)

                if let priority = task.priority {
                    Image(systemName: priority.symbolName)
                        .foregroundStyle(FunkeTheme.dim)
                        .accessibilityLabel(priority.displayName)
                }
            }
            .opacity(done ? 0.5 : 1)
        }
    }

    // MARK: - Zustände

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Lade Aufgaben…")
                .font(.system(size: 14))
                .foregroundStyle(FunkeTheme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(FunkeTheme.red)
            Text("Fehler")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(FunkeTheme.text)
            Text(error)
                .font(.system(size: 14))
                .foregroundStyle(FunkeTheme.dim)
                .multilineTextAlignment(.center)
            Button("Erneut laden") {
                Task { await viewModel.load() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(FunkeTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(FunkeTheme.accent)
            Text("Nichts für heute")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(FunkeTheme.text)
            Text("Keine fälligen oder überfälligen Aufgaben. Gut gemacht!")
                .font(.system(size: 14))
                .foregroundStyle(FunkeTheme.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helfer

    /// „Gestern fällig" / „Vorgestern fällig" / sonst Datum.
    private static func overdueText(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        switch days {
        case 1: return "Gestern fällig"
        case 2: return "Vorgestern fällig"
        default: return "Fällig \(date.formatted(date: .abbreviated, time: .omitted))"
        }
    }
}
