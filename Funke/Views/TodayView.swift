import SwiftUI

/// Heute fällige/überfällige Aufgaben, nach Priorität gruppiert.
/// Überfällige sind hervorgehoben; Abhaken via Swipe oder Button.
struct TodayView: View {
    @ObservedObject var viewModel: TodayViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Heute")
                .refreshable { await viewModel.load() }
                .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.sections.isEmpty {
            ProgressView("Lade Aufgaben…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.error {
            errorState(error)
        } else if viewModel.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(viewModel.sections) { section in
                Section(section.title) {
                    ForEach(section.tasks) { task in
                        row(task)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    Task { await viewModel.complete(task) }
                                } label: {
                                    Label("Erledigt", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ task: TodayTask) -> some View {
        let overdue = task.isOverdue()
        return HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await viewModel.complete(task) }
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(task.name) erledigen")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.name)
                    .font(.body)
                if let due = task.dueDate {
                    Label(Self.dueText(due), systemImage: overdue ? "exclamationmark.circle.fill" : "calendar")
                        .font(.caption)
                        .foregroundStyle(overdue ? .red : .secondary)
                }
            }

            Spacer()

            if let priority = task.priority {
                Image(systemName: priority.symbolName)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(priority.displayName)
            }
        }
        .padding(.vertical, 2)
    }

    private func errorState(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Fehler", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Erneut laden") {
                Task { await viewModel.load() }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nichts für heute", systemImage: "checkmark.circle")
        } description: {
            Text("Keine fälligen oder überfälligen Aufgaben. Gut gemacht!")
        }
    }

    private static func dueText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
