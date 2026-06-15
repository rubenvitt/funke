import SwiftUI

/// watchOS-App-Target (Single-Target SwiftUI Watch App, `WKApplication`).
/// Reines Quick-Capture, das per WatchConnectivity ans iPhone relayt.
@main
struct FunkeWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchCaptureView()
            }
        }
    }
}
