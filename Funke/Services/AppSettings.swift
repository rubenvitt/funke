import Foundation
import Combine

/// Nicht-geheime App-Einstellungen, persistiert in UserDefaults.
/// Secrets liegen ausschließlich im Keychain (siehe `SecretStoring`).
@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let enrichmentEnabled = "enrichmentEnabled"
        static let activeProvider = "activeProvider"
        static let openRouterModel = "openRouterModel"
        static let teamID = "teamID"
        static let inboxListID = "inboxListID"
        static let inboxListName = "inboxListName"
        static let relayBaseURL = "relayBaseURL"
        static let noteFolder = "noteFolder"
        static let vaultBookmark = "vaultBookmark"
    }

    /// Default-OpenRouter-Modell (günstig/schnell für Klassifikation).
    static let defaultOpenRouterModel = "openai/gpt-5-nano"

    private let defaults: UserDefaults

    @Published var enrichmentEnabled: Bool {
        didSet { defaults.set(enrichmentEnabled, forKey: Keys.enrichmentEnabled) }
    }
    @Published var activeProvider: EnrichmentProviderKind {
        didSet { defaults.set(activeProvider.rawValue, forKey: Keys.activeProvider) }
    }
    @Published var openRouterModel: String {
        didSet { defaults.set(openRouterModel, forKey: Keys.openRouterModel) }
    }
    @Published var teamID: String? {
        didSet { Self.write(teamID, Keys.teamID, defaults) }
    }
    @Published var inboxListID: String? {
        didSet { Self.write(inboxListID, Keys.inboxListID, defaults) }
    }
    @Published var inboxListName: String? {
        didSet { Self.write(inboxListName, Keys.inboxListName, defaults) }
    }

    // MARK: - Notiz-Transport (Relay-Server / lokaler Vault)

    /// Basis-URL des Funke-Relay-Servers (z. B. `https://funke.example.ts.net`).
    /// iOS/Watch nutzen sie; macOS schreibt stattdessen direkt ins lokale Vault.
    @Published var relayBaseURL: String {
        didSet { defaults.set(relayBaseURL, forKey: Keys.relayBaseURL) }
    }
    /// Vault-relativer Ordner für neue Notizen (z. B. „Inbox").
    @Published var noteFolder: String {
        didSet { defaults.set(noteFolder, forKey: Keys.noteFolder) }
    }
    /// macOS: Security-Scoped Bookmark auf das lokale Vault-Verzeichnis (`~/r-notes`).
    @Published var vaultBookmark: Data? {
        didSet {
            if let vaultBookmark { defaults.set(vaultBookmark, forKey: Keys.vaultBookmark) }
            else { defaults.removeObject(forKey: Keys.vaultBookmark) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enrichmentEnabled = defaults.bool(forKey: Keys.enrichmentEnabled)
        self.activeProvider = EnrichmentProviderKind(rawValue: defaults.string(forKey: Keys.activeProvider) ?? "")
            ?? .appleOnDevice
        self.openRouterModel = defaults.string(forKey: Keys.openRouterModel) ?? Self.defaultOpenRouterModel
        self.teamID = defaults.string(forKey: Keys.teamID)
        self.inboxListID = defaults.string(forKey: Keys.inboxListID)
        self.inboxListName = defaults.string(forKey: Keys.inboxListName)
        self.relayBaseURL = defaults.string(forKey: Keys.relayBaseURL) ?? ""
        self.noteFolder = defaults.string(forKey: Keys.noteFolder) ?? "Inbox"
        self.vaultBookmark = defaults.data(forKey: Keys.vaultBookmark)
    }

    /// True, sobald eine Inbox-Liste gewählt wurde.
    var isInboxConfigured: Bool {
        guard let inboxListID, !inboxListID.isEmpty else { return false }
        return true
    }

    /// Aktuelle nicht-geheime Capture-Konfiguration für den `CaptureRouter`.
    var routerConfig: CaptureRouterConfig {
        CaptureRouterConfig(
            inboxListID: inboxListID,
            noteFolder: noteFolder,
            enrichmentEnabled: enrichmentEnabled,
            provider: activeProvider,
            openRouterModel: openRouterModel
        )
    }

    private static func write(_ value: String?, _ key: String, _ defaults: UserDefaults) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
