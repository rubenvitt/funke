import AppIntents

/// Freihändiges Quick-Capture per Siri / Action-Button / CarPlay-Siri.
/// Läuft im Hintergrund (App bleibt unsichtbar), klassifiziert + routet über den
/// geteilten `CaptureRouter` und gibt eine **gesprochene** Bestätigung zurück.
///
/// Liegt bewusst im App-Target (keine Extension) → derselbe Keychain/UserDefaults
/// ohne App Group. Während der Fahrt zulässig, weil reiner Background-/Audio-Dialog.
struct CaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "In Funke erfassen"
    static let description = IntentDescription(
        "Erfasst per Sprache eine Notiz oder Aufgabe in Funke.",
        categoryName: "Erfassen"
    )

    /// Hält die App im Hintergrund (freihändig, kein Foregrounding).
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Text", requestValueDialog: IntentDialog("Was möchtest du festhalten?"))
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return .result(dialog: "Ich habe nichts verstanden.")
        }

        let services = CaptureServices.make()
        do {
            let outcome = try await services.router.route(rawText: raw, config: services.settings.routerConfig)
            switch outcome {
            case .task(let queued):
                return .result(dialog: queued ? "Aufgabe offline gepuffert." : "Aufgabe angelegt.")
            case .note(let queued):
                return .result(dialog: queued ? "Notiz offline gepuffert." : "Notiz gespeichert.")
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Konnte nicht erfassen."
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
    }
}

/// Deutsche Auslöser-Phrasen. Freitext kommt nicht über die Phrase (nur Enum/Entity
/// möglich), sondern über die `requestValueDialog`-Nachfrage des Intents.
struct FunkeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(),
            phrases: [
                "Erfasse in \(.applicationName)",
                "\(.applicationName) Notiz",
                "Neue Notiz in \(.applicationName)",
                "Halte in \(.applicationName) fest"
            ],
            shortTitle: "Erfassen",
            systemImageName: "square.and.pencil"
        )
    }
}
