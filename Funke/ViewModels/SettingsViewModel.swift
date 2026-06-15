import Foundation
import Combine

/// Verwaltet ClickUp-Verbindung, Inbox-Auswahl und KI-Provider-Einstellungen.
/// Token/Schlüssel liegen ausschließlich im Keychain; alle Aktionen melden
/// sichtbar OK/Fehler — kein stilles Schlucken.
@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - ClickUp-Token / Verbindung

    /// Spiegel des im Keychain hinterlegten Tokens (zur Bearbeitung im Feld).
    @Published var clickUpToken: String = ""
    @Published var connectionStatus: StatusMessage?
    @Published var isTestingConnection: Bool = false

    // MARK: - API-Schlüssel

    @Published var anthropicKey: String = ""
    @Published var openRouterKey: String = ""
    @Published var keyStatus: StatusMessage?

    // MARK: - Workspace / Inbox

    @Published var teams: [ClickUpTeam] = []
    @Published var spaces: [ClickUpSpace] = []
    @Published var folders: [ClickUpFolder] = []
    @Published var folderlessLists: [ClickUpList] = []
    @Published var folderLists: [ClickUpList] = []
    @Published var isLoadingHierarchy: Bool = false
    @Published var hierarchyError: String?

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

    private let clickUp: ClickUpClienting
    private let secrets: SecretStoring
    private let enrichment: EnrichmentServicing

    /// - Note: Gegenüber der Spec-Skizze `init(clickUp:secrets:settings:)` um
    ///   `enrichment` erweitert, um die Provider-Verfügbarkeit anzuzeigen.
    init(
        clickUp: ClickUpClienting,
        secrets: SecretStoring,
        settings: AppSettings,
        enrichment: EnrichmentServicing
    ) {
        self.clickUp = clickUp
        self.secrets = secrets
        self.settings = settings
        self.enrichment = enrichment
        self.clickUpToken = secrets.string(for: .clickUpToken) ?? ""
        self.anthropicKey = secrets.string(for: .anthropicKey) ?? ""
        self.openRouterKey = secrets.string(for: .openRouterKey) ?? ""
        self.relayToken = secrets.string(for: .relayToken) ?? ""
    }

    // MARK: - Token / Schlüssel speichern

    /// Speichert das ClickUp-Token im Keychain (leer = löschen).
    func saveToken() {
        let trimmed = clickUpToken.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try secrets.setString(trimmed.isEmpty ? nil : trimmed, for: .clickUpToken)
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

    /// Testet die Verbindung über `authorizedUser` und lädt anschließend die Workspaces.
    func testConnection() async {
        let trimmed = clickUpToken.trimmingCharacters(in: .whitespacesAndNewlines)
        // Aktuellen Tokenstand sichern, damit der Client ihn lesen kann.
        do {
            try secrets.setString(trimmed.isEmpty ? nil : trimmed, for: .clickUpToken)
        } catch {
            connectionStatus = .failure(Self.message(from: error))
            return
        }

        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            let user = try await clickUp.authorizedUser()
            let name = user.username ?? "Nutzer #\(user.id)"
            connectionStatus = .success("Verbunden als \(name).")
            await loadTeams()
        } catch {
            connectionStatus = .failure(Self.message(from: error))
        }
    }

    // MARK: - Workspace / Inbox laden

    func loadTeams() async {
        isLoadingHierarchy = true
        hierarchyError = nil
        defer { isLoadingHierarchy = false }
        do {
            teams = try await clickUp.teams()
        } catch {
            hierarchyError = Self.message(from: error)
        }
    }

    /// Wählt einen Workspace und lädt dessen Spaces.
    func selectTeam(_ team: ClickUpTeam) async {
        settings.teamID = team.id
        spaces = []
        folders = []
        folderlessLists = []
        folderLists = []
        await loadSpaces(teamID: team.id)
    }

    func loadSpaces(teamID: String) async {
        isLoadingHierarchy = true
        hierarchyError = nil
        defer { isLoadingHierarchy = false }
        do {
            spaces = try await clickUp.spaces(teamID: teamID)
        } catch {
            hierarchyError = Self.message(from: error)
        }
    }

    /// Lädt für einen Space die Ordner und die ordnerlosen Listen.
    func loadSpaceContents(spaceID: String) async {
        isLoadingHierarchy = true
        hierarchyError = nil
        defer { isLoadingHierarchy = false }
        do {
            async let foldersResult = clickUp.folders(spaceID: spaceID)
            async let folderlessResult = clickUp.folderlessLists(spaceID: spaceID)
            folders = try await foldersResult
            folderlessLists = try await folderlessResult
            folderLists = []
        } catch {
            hierarchyError = Self.message(from: error)
        }
    }

    /// Lädt die Listen eines Ordners.
    func loadFolderLists(folderID: String) async {
        isLoadingHierarchy = true
        hierarchyError = nil
        defer { isLoadingHierarchy = false }
        do {
            folderLists = try await clickUp.folderLists(folderID: folderID)
        } catch {
            hierarchyError = Self.message(from: error)
        }
    }

    /// Übernimmt eine Liste als Inbox-Ziel.
    func selectInbox(_ list: ClickUpList) {
        settings.inboxListID = list.id
        settings.inboxListName = list.name
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
