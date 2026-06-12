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
            // Beim Start die Offline-Queue nachsenden (nie stiller Verlust).
            .task {
                await container.capture.flushQueue()
            }
        }
    }
}
