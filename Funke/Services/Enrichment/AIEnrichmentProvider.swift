import Foundation

/// Die verfügbaren KI-Veredelungs-Provider.
enum EnrichmentProviderKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case appleOnDevice
    case appleCloud
    case anthropic
    case openRouter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleOnDevice: return "Apple On-Device"
        case .appleCloud: return "Apple Cloud (Private Cloud Compute)"
        case .anthropic: return "Anthropic (Claude)"
        case .openRouter: return "OpenRouter"
        }
    }

    /// Braucht dieser Provider einen API-Schlüssel?
    var requiresAPIKey: Bool {
        switch self {
        case .appleOnDevice, .appleCloud: return false
        case .anthropic, .openRouter: return true
        }
    }

    /// Welcher Keychain-Eintrag, falls ein Schlüssel nötig ist.
    var secretKey: SecretKey? {
        switch self {
        case .anthropic: return .anthropicKey
        case .openRouter: return .openRouterKey
        case .appleOnDevice, .appleCloud: return nil
        }
    }
}

/// Verfügbarkeit eines Providers im aktuellen Kontext.
enum ProviderAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var reason: String? {
        if case .unavailable(let r) = self { return r }
        return nil
    }
}

/// Ein einzelner KI-Provider, der rohen Text zu einem strukturierten Vorschlag veredelt.
protocol AIEnrichmentProvider: Sendable {
    var kind: EnrichmentProviderKind { get }
    func availability() async -> ProviderAvailability
    func enrich(_ rawText: String) async throws -> EnrichmentSuggestion
    /// Bereinigt eine rohe Notiz zu Titel + aufgeräumtem Markdown-Body.
    func enrichNote(_ rawText: String) async throws -> NoteSuggestion
}

/// Fasst alle Provider zusammen und wählt anhand der Einstellungen.
/// Die KI ist additiv und nie blockierend – Fehler werden geworfen, nie verschluckt.
protocol EnrichmentServicing: Sendable {
    func availability(for kind: EnrichmentProviderKind) async -> ProviderAvailability
    /// `openRouterModel` wird nur vom OpenRouter-Provider genutzt und sonst ignoriert.
    func enrich(
        _ rawText: String,
        using kind: EnrichmentProviderKind,
        openRouterModel: String
    ) async throws -> EnrichmentSuggestion
    /// Bereinigt eine rohe Notiz über den gewählten Provider.
    func enrichNote(
        _ rawText: String,
        using kind: EnrichmentProviderKind,
        openRouterModel: String
    ) async throws -> NoteSuggestion
}
