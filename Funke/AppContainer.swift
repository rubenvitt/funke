import Foundation
#if os(iOS)
import UIKit
#endif

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
    let noteSink: NoteSink
    let router: CaptureRouter

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

        // NoteSink löst pro Schreibvorgang die aktuelle Zielkonfiguration auf.
        let sink = LiveNoteSink(resolve: {
            await MainActor.run { AppContainer.buildSink(settings: settings, secrets: keychain) }
        })
        self.noteSink = sink

        let captureRouter = CaptureRouter(
            clickUp: clickUpClient, noteSink: sink, queue: offlineQueue, enrichment: enrichmentService
        )
        self.router = captureRouter

        self.capture = CaptureViewModel(
            router: captureRouter,
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

    /// Wählt den plattformgerechten NoteSink: macOS schreibt (bei vorhandenem
    /// Bookmark) direkt ins lokale Vault, iOS/sonst über den Relay-Server.
    @MainActor
    static func buildSink(settings: AppSettings, secrets: SecretStoring) -> NoteSink? {
        #if os(macOS)
        if let bookmark = settings.vaultBookmark, let root = resolveBookmark(bookmark) {
            return LocalFileNoteSink(vaultRoot: root, folder: settings.noteFolder)
        }
        #endif
        let trimmed = settings.relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let base = URL(string: trimmed) else { return nil }
        let token = secrets.string(for: .relayToken) ?? ""
        return RelayNoteSink(baseURL: base, token: token, folder: settings.noteFolder)
    }

    #if os(macOS)
    /// Löst das Security-Scoped Bookmark auf und beginnt den Zugriff.
    static func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
    #endif
}
