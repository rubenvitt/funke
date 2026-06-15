import SwiftUI

extension Color {
    /// Plattform-adaptiver Feld-/Karten-Hintergrund (iOS-Systemfarbe bzw. macOS-Äquivalent).
    static var fieldBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.gray.opacity(0.2)
        #endif
    }
}

extension View {
    /// Eingabefeld ohne Auto-Korrektur/Auto-Großschreibung — cross-platform
    /// (`textInputAutocapitalization` gibt es nur auf iOS).
    func plainTextInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }

    /// Kompakter Navigationstitel auf iOS; no-op auf macOS
    /// (`navigationBarTitleDisplayMode` gibt es nur auf iOS).
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
