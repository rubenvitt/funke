import SwiftUI

@main
struct FunkeApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView(
                capture: container.capture,
                today: container.today,
                settings: container.settingsViewModel
            )
            .task {
                #if os(iOS)
                // Watch-Relay-Empfang aktivieren (verarbeitet eingehende Captures).
                PhoneRelay.shared.start()
                #endif
                // Beim Start die Offline-Queue nachsenden (nie stiller Verlust).
                await container.capture.flushQueue()
            }
        }
    }
}
