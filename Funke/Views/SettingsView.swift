import SwiftUI

/// Einstellungen: Zunder-Verbindung, KI-Provider und Notiz-Transport.
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var settings: AppSettings

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
    }

    var body: some View {
        NavigationStack {
            Form {
                zunderSection
                aiSection
                relaySection
            }
            .navigationTitle("Einstellungen")
        }
    }

    // MARK: - Zunder

    private var zunderSection: some View {
        Section("Zunder") {
            TextField("Server-URL (https://…)", text: $settings.zunderBaseURL)
                .plainTextInput()

            SecureField("API-Token (zt_…)", text: $viewModel.zunderToken)
                .plainTextInput()

            Button {
                Task { await viewModel.testConnection() }
            } label: {
                HStack {
                    Text("Verbindung testen")
                    Spacer()
                    if viewModel.isTestingConnection {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isTestingConnection)

            statusRow(viewModel.connectionStatus)

            Text("Aufgaben landen in der Zunder-Inbox. Das API-Token erzeugst du in der Zunder-Web-UI unter „Tokens“; „Verbindung testen“ speichert es im Schlüsselbund.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - KI

    private var aiSection: some View {
        Section("KI-Veredelung") {
            Toggle("KI aktiv", isOn: enrichmentBinding)

            Picker("Provider", selection: providerBinding) {
                ForEach(EnrichmentProviderKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            LabeledContent("Verfügbarkeit") {
                if viewModel.isCheckingProvider {
                    ProgressView()
                } else {
                    Text(viewModel.availabilityText)
                        .foregroundStyle(
                            viewModel.providerAvailability?.isAvailable == true ? .green : .secondary
                        )
                }
            }

            if settings.activeProvider == .openRouter {
                TextField("OpenRouter-Modell", text: $settings.openRouterModel)
                    .plainTextInput()
            }

            if settings.activeProvider.requiresAPIKey {
                SecureField("Anthropic-Schlüssel", text: $viewModel.anthropicKey)
                    .plainTextInput()
                SecureField("OpenRouter-Schlüssel", text: $viewModel.openRouterKey)
                    .plainTextInput()
                Button("Schlüssel speichern") { viewModel.saveAPIKeys() }
                statusRow(viewModel.keyStatus)
            }
        }
        .task { await viewModel.checkProviderAvailability() }
    }

    // MARK: - Relay (Notiz-Transport)

    private var relaySection: some View {
        Section("Notiz-Transport (Relay)") {
            TextField("Relay-URL (https://…)", text: $settings.relayBaseURL)
                .plainTextInput()

            SecureField("Relay-Token", text: $viewModel.relayToken)
                .plainTextInput()

            TextField("Notiz-Ordner im Vault", text: $settings.noteFolder)
                .plainTextInput()

            #if os(macOS)
            // macOS schreibt direkt ins lokale Vault, wenn ein Ordner gewählt ist.
            LabeledContent("Lokales Vault") {
                Text(settings.vaultBookmark == nil ? "nicht gewählt" : "gewählt")
                    .foregroundStyle(settings.vaultBookmark == nil ? Color.secondary : Color.green)
            }
            Button("Vault-Ordner wählen…") {
                if let bookmark = MacVaultAccess.pickVaultBookmark() {
                    settings.vaultBookmark = bookmark
                }
            }
            #endif

            Button("Token speichern") { viewModel.saveRelayToken() }

            Button {
                Task { await viewModel.testRelay() }
            } label: {
                HStack {
                    Text("Relay testen")
                    Spacer()
                    if viewModel.isTestingRelay { ProgressView() }
                }
            }
            .disabled(viewModel.isTestingRelay)

            statusRow(viewModel.relayStatus)

            Text("Notizen gehen an deinen Relay-Server (obsidian-headless); Obsidian Sync verteilt sie. Auf dem Mac kann Funke stattdessen direkt ins lokale Vault schreiben.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private var providerBinding: Binding<EnrichmentProviderKind> {
        Binding(
            get: { settings.activeProvider },
            set: { newValue in Task { await viewModel.selectProvider(newValue) } }
        )
    }

    private var enrichmentBinding: Binding<Bool> {
        Binding(
            get: { settings.enrichmentEnabled },
            set: { viewModel.setEnrichmentEnabled($0) }
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusRow(_ status: SettingsViewModel.StatusMessage?) -> some View {
        if let status {
            switch status {
            case .success(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }
}
