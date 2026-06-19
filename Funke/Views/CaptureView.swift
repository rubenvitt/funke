import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Schnellerfassung im Glut-Look: Wortmarke, großes Eingabefeld (sofort
/// fokussiert), runder Senden-Button mit Funken-Animation, Mic-Toggle,
/// Modus-Picker, „Letzte Funken"-Liste, Toast und das Review-Sheet.
struct CaptureView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @FocusState private var isTextFocused: Bool

    // Aufsteigende Akzent-Partikel beim Senden (rein dekorativ).
    @State private var particles: [SparkParticle] = []
    @State private var particleSeed = 0

    var body: some View {
        ZStack {
            // Glut-Hintergrund bis unter die Safe Areas.
            FunkeTheme.background.ignoresSafeArea()
            content
        }
        // Toast unten einblenden (nur Erfolg/Status, Fehler laufen über Banner).
        .overlay(alignment: .bottom) { toastOverlay }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.toast)
        .safeAreaInset(edge: .bottom) {
            // Steuerleiste sitzt ÜBER der Tastatur und bleibt erreichbar, ohne
            // dass der Nutzer abschicken muss, um an die TabView-Leiste zu kommen.
            controls
        }
        .task {
            await viewModel.refreshPendingCount()
            await viewModel.flushQueue()
            await viewModel.refreshHistory()
            isTextFocused = true
        }
        // Toast nach kurzer Anzeige automatisch wieder ausblenden.
        .task(id: viewModel.toast) {
            guard viewModel.toast != nil else { return }
            try? await Task.sleep(for: .milliseconds(1700))
            viewModel.toast = nil
        }
        // Senden löst eine kurze Funken-Animation aus.
        .onChange(of: viewModel.sparkBurst) { _, _ in emitParticles() }
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

    // MARK: - Aufbau

    private var content: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 8)

            banner
                .padding(.top, 12)

            // Tippen auf den Leerraum schließt die Tastatur, ohne zu erfassen —
            // so bleibt die TabView-Leiste erreichbar.
            Spacer(minLength: 16)
                .contentShape(Rectangle())
                .onTapGesture { isTextFocused = false }

            inputArea

            Spacer(minLength: 16)
                .contentShape(Rectangle())
                .onTapGesture { isTextFocused = false }

            if viewModel.pendingCount > 0 {
                pendingHint
                    .padding(.bottom, 10)
            }

            recentSparks

            actionRow
                .padding(.top, 16)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Kopfzeile

    private var header: some View {
        HStack(spacing: 9) {
            // Akzent-Punkt mit weichem Glut-Schatten.
            Circle()
                .fill(FunkeTheme.accent)
                .frame(width: 13, height: 13)
                .shadow(color: FunkeTheme.accent.opacity(0.6), radius: 6, x: 0, y: 1)
            Text("Funke")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(FunkeTheme.text)

            Spacer()

            Text(todaySparkLabel)
                .font(.system(size: 14))
                .foregroundStyle(FunkeTheme.dim)
        }
    }

    /// „1 Funke heute" / „N Funken heute".
    private var todaySparkLabel: String {
        let count = viewModel.todaySparkCount
        let noun = count == 1 ? "Funke" : "Funken"
        return "\(count) \(noun) heute"
    }

    // MARK: - Fehler-Banner (nur noch für Fehler)

    @ViewBuilder
    private var banner: some View {
        if case .failure(let message) = viewModel.banner {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FunkeTheme.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(FunkeTheme.redBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(FunkeTheme.redLine, lineWidth: 1)
                )
        }
    }

    // MARK: - Eingabe (vertikal zentriert mit dezentem Glow)

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Neuer Funke → Inbox")
                .funkeSectionLabel()

            TextField(
                "Was ist der Funke?",
                text: $viewModel.text,
                axis: .vertical
            )
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(FunkeTheme.text)
            .tint(FunkeTheme.accent) // Caret in Akzentfarbe
            .textFieldStyle(.plain)
            .lineLimit(1...8)
            .focused($isTextFocused)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .center) {
            // Weicher radialer Akzent-Glow hinter dem Eingabefeld.
            RadialGradient(
                colors: [FunkeTheme.accentSoft, .clear],
                center: .center,
                startRadius: 0,
                endRadius: 260
            )
            .blur(radius: 12)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Offline-Hinweis

    private var pendingHint: some View {
        Label("\(viewModel.pendingCount) offline gepuffert", systemImage: "tray.full")
            .font(.system(size: 13))
            .foregroundStyle(FunkeTheme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Letzte Funken

    @ViewBuilder
    private var recentSparks: some View {
        if !viewModel.recentSparks.isEmpty {
            VStack(spacing: 0) {
                ForEach(viewModel.recentSparks) { spark in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(FunkeTheme.accent)
                            .frame(width: 6, height: 6)
                        Text(spark.text)
                            .font(.system(size: 14))
                            .foregroundStyle(FunkeTheme.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 12)
                        Text(spark.date.formatted(.relative(presentation: .named)))
                            .font(.system(size: 12))
                            .foregroundStyle(FunkeTheme.dim)
                    }
                    .padding(.vertical, 10)

                    if spark.id != viewModel.recentSparks.last?.id {
                        Rectangle()
                            .fill(FunkeTheme.line2)
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: - Aktionszeile (Hilfetext + Senden)

    private var actionRow: some View {
        HStack(alignment: .bottom, spacing: 16) {
            Text("Landet in **Inbox** · KI veredelt Titel, Liste & Datum.")
                .font(.system(size: 12))
                .foregroundStyle(FunkeTheme.dim)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            sendButton
        }
    }

    private var sendButton: some View {
        Button {
            isTextFocused = false
            Task { await viewModel.capture() }
        } label: {
            Group {
                if viewModel.isWorking {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 22, weight: .bold))
                }
            }
        }
        .buttonStyle(AccentCircleButtonStyle())
        .disabled(isSendDisabled)
        .opacity(isSendDisabled ? 0.5 : 1)
        // Funken steigen aus dem Senden-Button auf.
        .overlay(alignment: .top) {
            ZStack {
                ForEach(particles) { particle in
                    SparkParticleView(particle: particle)
                }
            }
            .offset(y: -8)
            .allowsHitTesting(false)
        }
        .accessibilityLabel("Funke erfassen")
    }

    private var isSendDisabled: Bool {
        viewModel.isWorking ||
        viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Steuerleiste (Mic + Modus + Tastatur schließen)

    private var controls: some View {
        HStack(spacing: 12) {
            // Mic-Toggle — rot, solange aufgenommen wird.
            Button {
                Task { await viewModel.toggleRecording() }
            } label: {
                Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(viewModel.isRecording ? FunkeTheme.redBg : FunkeTheme.surface2)
                    )
                    .overlay(
                        Circle().strokeBorder(
                            viewModel.isRecording ? FunkeTheme.redLine : FunkeTheme.line,
                            lineWidth: 1
                        )
                    )
                    .foregroundStyle(viewModel.isRecording ? FunkeTheme.red : FunkeTheme.text)
            }
            .accessibilityLabel(viewModel.isRecording ? "Aufnahme stoppen" : "Aufnahme starten")

            // Modus-Picker (Auto/Task/Notiz).
            Picker("", selection: $viewModel.mode) {
                ForEach(CaptureViewModel.CaptureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(FunkeTheme.accent)
            .frame(maxWidth: .infinity)

            // Tastatur einklappen, ohne zu erfassen — gibt die TabView-Leiste frei.
            Button {
                isTextFocused = false
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(FunkeTheme.surface2))
                    .overlay(Circle().strokeBorder(FunkeTheme.line, lineWidth: 1))
                    .foregroundStyle(FunkeTheme.text)
            }
            .accessibilityLabel("Tastatur schließen")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(alignment: .top) {
            FunkeTheme.surface
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle().fill(FunkeTheme.line).frame(height: 1)
                }
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = viewModel.toast {
            FunkeToast(message: toast)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Funken-Partikel

    /// Erzeugt eine Handvoll aufsteigender Akzent-Kreise und räumt sie nach
    /// Ablauf der Animation wieder ab. Zufall nur im Event-Handler, nie im
    /// Render-Pfad.
    private func emitParticles() {
        var fresh: [SparkParticle] = []
        for index in 0..<7 {
            fresh.append(
                SparkParticle(
                    id: particleSeed + index,
                    xJitter: CGFloat.random(in: -26...26),
                    size: CGFloat.random(in: 5...10),
                    delay: Double.random(in: 0...0.14)
                )
            )
        }
        particleSeed += fresh.count
        particles.append(contentsOf: fresh)

        let ids = Set(fresh.map(\.id))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            particles.removeAll { ids.contains($0.id) }
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

// MARK: - Funken-Partikel-Modell & -View

/// Ein einzelner aufsteigender Funke (rein dekorativ).
private struct SparkParticle: Identifiable {
    let id: Int
    let xJitter: CGFloat
    let size: CGFloat
    let delay: Double
}

/// Animiert einen Funken: steigt auf, verblasst und schrumpft leicht.
private struct SparkParticleView: View {
    let particle: SparkParticle
    @State private var rise = false

    var body: some View {
        Circle()
            .fill(FunkeTheme.accent)
            .frame(width: particle.size, height: particle.size)
            .offset(x: particle.xJitter, y: rise ? -96 : 0)
            .opacity(rise ? 0 : 0.9)
            .scaleEffect(rise ? 0.4 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.9).delay(particle.delay)) {
                    rise = true
                }
            }
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
