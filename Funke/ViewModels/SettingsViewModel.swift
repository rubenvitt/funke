import Foundation
import Combine

/// Verwaltet Zunder-Verbindung und KI-Provider-Einstellungen.
/// Token/Schlüssel liegen ausschließlich im Keychain; alle Aktionen melden
/// sichtbar OK/Fehler — kein stilles Schlucken.
@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - Zunder-Token / Verbindung

    /// Spiegel des im Keychain hinterlegten API-Tokens (zur Bearbeitung im Feld).
    @Published var zunderToken: String = ""
    @Published var connectionStatus: StatusMessage?
    @Published var isTestingConnection: Bool = false

    // MARK: - API-Schlüssel

    @Published var anthropicKey: String = ""
    @Published var openRouterKey: String = ""
    @Published var keyStatus: StatusMessage?

    // MARK: - KI-Verfügbarkeit

    @Published var providerAvailability: ProviderAvailability?
    @Published var isCheckingProvider: Bool = false

    // MARK: - Relay (Notiz-Transport)

    /// Spiegel des im Keychain hinterlegten Relay-Tokens (zur Bearbeitung im Feld).
    @Published var relayToken: String = ""
    @Published var relayStatus: StatusMessage?
    @Published var isTestingRelay: Bool = false

    /// Sichtbare Status- bzw. Fehlermeldung mit Erfolgs-/Fehler-Kennung.
    enum StatusMessage: Equatable {
        case success(String)
        case failure(String)
    }

    let settings: AppSettings

    private let zunder: ZunderClienting
    private let secrets: SecretStoring
    private let enrichment: EnrichmentServicing

    init(
        zunder: ZunderClienting,
        secrets: SecretStoring,
        settings: AppSettings,
        enrichment: EnrichmentServicing
    ) {
        self.zunder = zunder
        self.secrets = secrets
        self.settings = settings
        self.enrichment = enrichment
        self.zunderToken = secrets.string(for: .zunderToken) ?? ""
        self.anthropicKey = secrets.string(for: .anthropicKey) ?? ""
        self.openRouterKey = secrets.string(for: .openRouterKey) ?? ""
        self.relayToken = secrets.string(for: .relayToken) ?? ""
    }

    /// Server-URL und Token hinterlegt?
    var isZunderConfigured: Bool {
        settings.isZunderConfigured(secrets: secrets)
    }

    // MARK: - Token / Schlüssel speichern

    /// Speichert das Zunder-API-Token im Keychain (leer = löschen).
    func saveToken() {
        let trimmed = zunderToken.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try secrets.setString(trimmed.isEmpty ? nil : trimmed, for: .zunderToken)
            connectionStatus = .success(trimmed.isEmpty ? "Token entfernt." : "Token gespeichert.")
        } catch {
            connectionStatus = .failure(Self.message(from: error))
        }
    }

    /// Speichert beide KI-Schlüssel im Keychain (leer = löschen).
    func saveAPIKeys() {
        do {
            let a = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let o = openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try secrets.setString(a.isEmpty ? nil : a, for: .anthropicKey)
            try secrets.setString(o.isEmpty ? nil : o, for: .openRouterKey)
            keyStatus = .success("Schlüssel gespeichert.")
        } catch {
            keyStatus = .failure(Self.message(from: error))
        }
    }

    // MARK: - Verbindung testen

    /// Sichert das eingetragene Token und prüft die Verbindung über `GET /api/me`.
    func testConnection() async {
        let trimmed = zunderToken.trimmingCharacters(in: .whitespacesAndNewlines)
        // Aktuellen Tokenstand sichern, damit der Client ihn lesen kann.
        do {
            try secrets.setString(trimmed.isEmpty ? nil : trimmed, for: .zunderToken)
        } catch {
            connectionStatus = .failure(Self.message(from: error))
            return
        }

        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            let user = try await zunder.currentUser()
            connectionStatus = .success("Verbunden als \(user.displayName).")
        } catch {
            connectionStatus = .failure(Self.message(from: error))
        }
    }

    // MARK: - KI-Provider

    /// Setzt den aktiven Provider und prüft direkt dessen Verfügbarkeit.
    func selectProvider(_ kind: EnrichmentProviderKind) async {
        settings.activeProvider = kind
        await checkProviderAvailability()
    }

    /// Liefert Anzeigetext zur Verfügbarkeit des aktuell gewählten Providers.
    func checkProviderAvailability() async {
        isCheckingProvider = true
        defer { isCheckingProvider = false }
        providerAvailability = await enrichment.availability(for: settings.activeProvider)
    }

    /// Menschlich lesbarer Verfügbarkeitstext für die View.
    var availabilityText: String {
        guard let providerAvailability else { return "Verfügbarkeit unbekannt." }
        switch providerAvailability {
        case .available:
            return "Verfügbar."
        case .unavailable(let reason):
            return "Nicht verfügbar: \(reason)"
        }
    }

    /// Schaltet die KI-Veredelung an/aus.
    func setEnrichmentEnabled(_ enabled: Bool) {
        settings.enrichmentEnabled = enabled
    }

    // MARK: - Relay (Notiz-Transport)

    /// Speichert das Relay-Token im Keychain (leer = löschen).
    func saveRelayToken() {
        let trimmed = relayToken.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try secrets.setString(trimmed.isEmpty ? nil : trimmed, for: .relayToken)
            relayStatus = .success(trimmed.isEmpty ? "Relay-Token entfernt." : "Relay-Token gespeichert.")
        } catch {
            relayStatus = .failure(Self.message(from: error))
        }
    }

    /// Prüft die Erreichbarkeit des Relay-Servers über `GET <relayBaseURL>/health`.
    func testRelay() async {
        let base = settings.relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let url = URL(string: base)?.appendingPathComponent("health") else {
            relayStatus = .failure("Keine gültige Relay-URL hinterlegt.")
            return
        }

        isTestingRelay = true
        defer { isTestingRelay = false }

        var request = URLRequest(url: url)
        let token = (secrets.string(for: .relayToken) ?? relayToken).trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if (200...299).contains(code) {
                relayStatus = .success("Relay erreichbar (HTTP \(code)).")
            } else {
                relayStatus = .failure("Relay antwortete mit HTTP \(code).")
            }
        } catch {
            relayStatus = .failure("Relay nicht erreichbar: \(error.localizedDescription)")
        }
    }

    private static func message(from error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
