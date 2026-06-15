import Foundation
#if os(macOS)
import AppKit

/// macOS: Ordnerwahl für den lokalen Vault (`~/r-notes`) via `NSOpenPanel` und
/// Security-Scoped Bookmark. Das Bookmark wird in `AppSettings.vaultBookmark`
/// persistiert; `AppContainer.buildSink` löst es bei jedem Schreibvorgang auf.
@MainActor
enum MacVaultAccess {
    /// Zeigt den Open-Panel und liefert ein Security-Scoped Bookmark (oder `nil`).
    static func pickVaultBookmark() -> Data? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Vault wählen"
        panel.message = "Wähle deinen Obsidian-Vault-Ordner (z. B. ~/r-notes)."

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
#endif
