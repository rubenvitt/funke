import SwiftUI

/// Wurzel-Tabbar: Erfassen, Heute, Einstellungen.
struct RootView: View {
    @ObservedObject var capture: CaptureViewModel
    @ObservedObject var today: TodayViewModel
    @ObservedObject var settings: SettingsViewModel

    var body: some View {
        TabView {
            CaptureView(viewModel: capture)
                .tabItem {
                    Label("Erfassen", systemImage: "square.and.pencil")
                }

            TodayView(viewModel: today)
                .tabItem {
                    Label("Heute", systemImage: "checklist")
                }

            SettingsView(viewModel: settings)
                .tabItem {
                    Label("Einstellungen", systemImage: "gearshape")
                }
        }
    }
}
