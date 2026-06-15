import SwiftUI

/// Editierbares Review eines KI-Vorschlags vor dem Anlegen.
struct EnrichmentReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var details: String
    @State private var priority: Priority

    private let onConfirm: (EnrichmentSuggestion) -> Void
    private let onCancel: () -> Void

    init(
        suggestion: EnrichmentSuggestion,
        onConfirm: @escaping (EnrichmentSuggestion) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _title = State(initialValue: suggestion.title)
        _details = State(initialValue: suggestion.details ?? "")
        _priority = State(initialValue: suggestion.priority)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Titel") {
                    TextField("Titel", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Beschreibung") {
                    TextField("Beschreibung (optional)", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Priorität") {
                    Picker("Priorität", selection: $priority) {
                        ForEach(Priority.allCases, id: \.self) { p in
                            Label(p.displayName, systemImage: p.symbolName).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("Vorschlag prüfen")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        onConfirm(makeSuggestion())
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func makeSuggestion() -> EnrichmentSuggestion {
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return EnrichmentSuggestion(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: trimmedDetails.isEmpty ? nil : trimmedDetails,
            priority: priority
        )
    }
}
