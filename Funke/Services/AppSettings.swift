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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enrichmentEnabled = defaults.bool(forKey: Keys.enrichmentEnabled)
        self.activeProvider = EnrichmentProviderKind(rawValue: defaults.string(forKey: Keys.activeProvider) ?? "")
            ?? .appleOnDevice
        self.openRouterModel = defaults.string(forKey: Keys.openRouterModel) ?? Self.defaultOpenRouterModel
        self.teamID = defaults.string(forKey: Keys.teamID)
        self.inboxListID = defaults.string(forKey: Keys.inboxListID)
        self.inboxListName = defaults.string(forKey: Keys.inboxListName)
    }

    /// True, sobald eine Inbox-Liste gewählt wurde.
    var isInboxConfigured: Bool {
        guard let inboxListID, !inboxListID.isEmpty else { return false }
        return true
    }

    private static func write(_ value: String?, _ key: String, _ defaults: UserDefaults) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
