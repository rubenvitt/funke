import Foundation

/// Composition-Root: erzeugt alle konkreten Services einmalig und verdrahtet
/// die ViewModels. Wird von `FunkeApp` als `@StateObject` gehalten, damit die
/// ViewModels über die App-Laufzeit stabil bleiben.
@MainActor
final class AppContainer: ObservableObject {
    let appSettings: AppSettings
    let secrets: SecretStoring
    let clickUp: ClickUpClienting
    let enrichment: EnrichmentServicing
    let queue: OfflineQueuing
    let transcriber: SpeechTranscriber

    let capture: CaptureViewModel
    let today: TodayViewModel
    let settingsViewModel: SettingsViewModel

    init() {
        let keychain = KeychainStore()
        let settings = AppSettings()
        let clickUpClient = ClickUpClient(secrets: keychain)
        let enrichmentService = EnrichmentService(secrets: keychain)
        let offlineQueue = OfflineQueue()
        let speech = SpeechTranscriber()

        self.secrets = keychain
        self.appSettings = settings
        self.clickUp = clickUpClient
        self.enrichment = enrichmentService
        self.queue = offlineQueue
        self.transcriber = speech

        self.capture = CaptureViewModel(
            clickUp: clickUpClient,
            enrichment: enrichmentService,
            settings: settings,
            queue: offlineQueue,
            transcriber: speech,
            onHaptic: { feedback in
                #if os(iOS)
                performHaptic(feedback)
                #endif
            }
        )
        self.today = TodayViewModel(clickUp: clickUpClient, settings: settings)
        self.settingsViewModel = SettingsViewModel(
            clickUp: clickUpClient,
            secrets: keychain,
            settings: settings,
            enrichment: enrichmentService
        )
    }
}
