import Foundation

/// Baut eine frische Capture-Service-Schicht (Router + Settings) aus Keychain +
/// UserDefaults. Geteilt von `AppContainer` (UI), `CaptureIntent` (App-Intent,
/// freihändig) und dem Watch-Empfänger — alle nutzen dieselbe Routing-/Queue-/
/// Classify-Logik. Frische Instanzen sind konsistent: die `OfflineQueue` teilt
/// dieselbe Datei, Clients lesen denselben Keychain/UserDefaults.
@MainActor
enum CaptureServices {
    static func make() -> (router: CaptureRouter, settings: AppSettings) {
        let keychain = KeychainStore()
        let settings = AppSettings()
        let drafts = ZunderOpFactory(node: ZunderNodeID.load(from: .standard))
        let zunder = AppContainer.makeZunderClient(secrets: keychain, factory: drafts)
        let enrichment = EnrichmentService(secrets: keychain)
        let queue = OfflineQueue()
        let sink = LiveNoteSink(resolve: {
            await MainActor.run { AppContainer.buildSink(settings: settings, secrets: keychain) }
        })
        let router = CaptureRouter(
            zunder: AppContainer.makeTaskClient(inner: zunder, secrets: keychain), drafts: drafts, noteSink: sink, queue: queue, enrichment: enrichment
        )
        return (router, settings)
    }
}
