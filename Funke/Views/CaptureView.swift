import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Schnellerfassung: großes Textfeld (sofort fokussiert), Mic-Toggle,
/// „Erfassen"-Button, Banner und das Review-Sheet für KI-Vorschläge.
struct CaptureView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @FocusState private var isTextFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                banner

                TextField(
                    "Was möchtest du erfassen?",
                    text: $viewModel.text,
                    axis: .vertical
                )
                .font(.title3)
                .lineLimit(4...12)
                .textFieldStyle(.plain)
                .focused($isTextFocused)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )

                if viewModel.pendingCount > 0 {
                    Label("\(viewModel.pendingCount) offline gepuffert", systemImage: "tray.full")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Tippen auf den leeren Hintergrund schließt die Tastatur,
                // ohne zu erfassen — so bleibt die TabView-Leiste erreichbar.
                Spacer()
                    .contentShape(Rectangle())
                    .onTapGesture { isTextFocused = false }
            }
            .padding()
            .navigationTitle("Erfassen")
            .navigationBarTitleDisplayMode(.inline)
            // Steuerleiste sitzt ÜBER der Tastatur und bleibt erreichbar, ohne
            // dass der Nutzer abschicken muss, um an die TabView-Leiste zu kommen.
            .safeAreaInset(edge: .bottom) {
                controls
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(.bar)
            }
            .task {
                await viewModel.refreshPendingCount()
                await viewModel.flushQueue()
                isTextFocused = true
            }
            .sheet(item: reviewBinding) { identified in
                EnrichmentReviewView(
                    suggestion: identified.suggestion,
                    onConfirm: { edited in
                        Task { await viewModel.confirm(edited) }
                    },
                    onCancel: {
                        viewModel.cancelReview()
                    }
                )
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var banner: some View {
        if let banner = viewModel.banner {
            switch banner {
            case .success(let message):
                bannerLabel(message, systemImage: "checkmark.circle.fill", color: .green)
            case .failure(let message):
                bannerLabel(message, systemImage: "exclamationmark.triangle.fill", color: .orange)
            }
        }
    }

    private func bannerLabel(_ message: String, systemImage: String, color: Color) -> some View {
        Label(message, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12))
            )
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("", selection: $viewModel.mode) {
                ForEach(CaptureViewModel.CaptureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.toggleRecording() }
                } label: {
                    Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
                        .font(.title2)
                        .frame(width: 52, height: 52)
                        .background(
                            Circle().fill(
                                viewModel.isRecording
                                    ? Color.red.opacity(0.2)
                                    : Color(.secondarySystemBackground)
                            )
                        )
                        .foregroundStyle(viewModel.isRecording ? .red : .primary)
                }
                .accessibilityLabel(viewModel.isRecording ? "Aufnahme stoppen" : "Aufnahme starten")

                Button {
                    isTextFocused = false
                    Task { await viewModel.capture() }
                } label: {
                    HStack {
                        if viewModel.isWorking {
                            ProgressView()
                        }
                        Text(captureButtonTitle)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.isWorking ||
                    viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                // Tastatur einklappen, ohne zu erfassen — gibt die TabView-Leiste frei.
                Button {
                    isTextFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.title2)
                        .frame(width: 52, height: 52)
                        .background(
                            Circle().fill(Color(.secondarySystemBackground))
                        )
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Tastatur schließen")
            }
        }
    }

    /// Beschriftung des Haupt-Buttons je nach Erfassungsmodus.
    private var captureButtonTitle: String {
        switch viewModel.mode {
        case .task: return "Erfassen"
        case .note: return "Notiz speichern"
        }
    }

    /// Brückt `EnrichmentSuggestion?` (nicht `Identifiable`) auf ein `Identifiable`-Wrapper-Binding.
    private var reviewBinding: Binding<IdentifiedSuggestion?> {
        Binding(
            get: { viewModel.review.map(IdentifiedSuggestion.init) },
            set: { newValue in viewModel.review = newValue?.suggestion }
        )
    }
}

/// Hüllt einen `EnrichmentSuggestion` in eine `Identifiable`-Identität für `.sheet(item:)`.
/// Stabile `id`: Es gibt immer nur **ein** Review-Sheet gleichzeitig. Eine pro
/// `get` neu erzeugte UUID würde SwiftUI das Sheet während der Anzeige neu
/// präsentieren lassen (Flackern / verworfene Edits).
private struct IdentifiedSuggestion: Identifiable {
    let id = 0
    let suggestion: EnrichmentSuggestion
    init(_ suggestion: EnrichmentSuggestion) { self.suggestion = suggestion }
}

#if os(iOS)
/// Übersetzt `HapticFeedback` in echtes UIKit-Haptik-Feedback.
@MainActor
func performHaptic(_ feedback: HapticFeedback) {
    let generator = UINotificationFeedbackGenerator()
    switch feedback {
    case .success: generator.notificationOccurred(.success)
    case .warning: generator.notificationOccurred(.warning)
    case .error: generator.notificationOccurred(.error)
    }
}
#endif
