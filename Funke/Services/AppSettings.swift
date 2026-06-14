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
        static let obsidianVault = "obsidianVault"
        static let obsidianInboxFolder = "obsidianInboxFolder"
        static let obsidianNoteTarget = "obsidianNoteTarget"
        static let obsidianUseAdvancedURI = "obsidianUseAdvancedURI"
    }

    /// Default-OpenRouter-Modell (günstig/schnell für Klassifikation,
    /// live verifiziert mit structured-outputs-Unterstützung, Juni 2026).
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

    // MARK: - Obsidian (Notiz-Erfassung)

    /// Name des Obsidian-Vaults (leer = nicht konfiguriert).
    @Published var obsidianVault: String {
        didSet { defaults.set(obsidianVault, forKey: Keys.obsidianVault) }
    }
    /// Vault-relativer Ordner für neue Notizen.
    @Published var obsidianInboxFolder: String {
        didSet { defaults.set(obsidianInboxFolder, forKey: Keys.obsidianInboxFolder) }
    }
    /// Ziel neuer Notizen (neue Datei oder Tagesnotiz).
    @Published var obsidianNoteTarget: ObsidianNoteTarget {
        didSet { defaults.set(obsidianNoteTarget.rawValue, forKey: Keys.obsidianNoteTarget) }
    }
    /// Ob für die Tagesnotiz das Advanced-URI-Plugin genutzt werden soll.
    @Published var obsidianUseAdvancedURI: Bool {
        didSet { defaults.set(obsidianUseAdvancedURI, forKey: Keys.obsidianUseAdvancedURI) }
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
        self.obsidianVault = defaults.string(forKey: Keys.obsidianVault) ?? ""
        self.obsidianInboxFolder = defaults.string(forKey: Keys.obsidianInboxFolder) ?? "Inbox"
        self.obsidianNoteTarget = ObsidianNoteTarget(rawValue: defaults.string(forKey: Keys.obsidianNoteTarget) ?? "")
            ?? .inboxFile
        self.obsidianUseAdvancedURI = defaults.bool(forKey: Keys.obsidianUseAdvancedURI)
    }

    /// True, sobald eine Inbox-Liste gewählt wurde.
    var isInboxConfigured: Bool {
        guard let inboxListID, !inboxListID.isEmpty else { return false }
        return true
    }

    /// Aktuelle Obsidian-Konfiguration als Wertobjekt für den `ObsidianURLBuilder`.
    var obsidianConfig: ObsidianConfig {
        ObsidianConfig(
            vault: obsidianVault,
            inboxFolder: obsidianInboxFolder,
            target: obsidianNoteTarget,
            useAdvancedURI: obsidianUseAdvancedURI
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
