import SwiftUI

/// Einstellungen: ClickUp-Verbindung, Inbox-Auswahl und KI-Provider.
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
                clickUpSection
                workspaceSection
                inboxSection
                aiSection
            }
            .navigationTitle("Einstellungen")
        }
    }

    // MARK: - ClickUp

    private var clickUpSection: some View {
        Section("ClickUp") {
            SecureField("Personal Token (pk_…)", text: $viewModel.clickUpToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

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
        }
    }

    // MARK: - Workspace

    private var workspaceSection: some View {
        Section("Workspace") {
            if viewModel.teams.isEmpty {
                Text("Nach erfolgreichem Verbindungstest erscheinen hier deine Workspaces.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Workspace", selection: workspaceBinding) {
                    Text("Bitte wählen").tag(String?.none)
                    ForEach(viewModel.teams) { team in
                        Text(team.name).tag(Optional(team.id))
                    }
                }
            }

            if let error = viewModel.hierarchyError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Inbox

    private var inboxSection: some View {
        Section("Inbox-Liste") {
            if let name = settings.inboxListName {
                Label(name, systemImage: "tray")
            } else {
                Text("Noch keine Inbox gewählt.")
                    .foregroundStyle(.secondary)
            }

            if !viewModel.spaces.isEmpty {
                ForEach(viewModel.spaces) { space in
                    NavigationLink(space.name) {
                        SpaceListPicker(viewModel: viewModel, space: space)
                    }
                }
            } else if settings.teamID != nil {
                Button("Spaces laden") {
                    if let teamID = settings.teamID {
                        Task { await viewModel.loadSpaces(teamID: teamID) }
                    }
                }
            }
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
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if settings.activeProvider.requiresAPIKey {
                SecureField("Anthropic-Schlüssel", text: $viewModel.anthropicKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("OpenRouter-Schlüssel", text: $viewModel.openRouterKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Schlüssel speichern") { viewModel.saveAPIKeys() }
                statusRow(viewModel.keyStatus)
            }
        }
        .task { await viewModel.checkProviderAvailability() }
    }

    // MARK: - Bindings

    private var workspaceBinding: Binding<String?> {
        Binding(
            get: { settings.teamID },
            set: { newValue in
                guard let id = newValue, let team = viewModel.teams.first(where: { $0.id == id }) else { return }
                Task { await viewModel.selectTeam(team) }
            }
        )
    }

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

/// Bohrt von einem Space über Ordner/ordnerlose Listen bis zur Inbox-Liste.
private struct SpaceListPicker: View {
    @ObservedObject var viewModel: SettingsViewModel
    let space: ClickUpSpace

    var body: some View {
        List {
            if !viewModel.folderlessLists.isEmpty {
                Section("Listen") {
                    ForEach(viewModel.folderlessLists) { list in
                        listButton(list)
                    }
                }
            }
            if !viewModel.folders.isEmpty {
                Section("Ordner") {
                    ForEach(viewModel.folders) { folder in
                        NavigationLink(folder.name) {
                            FolderListPicker(viewModel: viewModel, folder: folder)
                        }
                    }
                }
            }
            if viewModel.folders.isEmpty && viewModel.folderlessLists.isEmpty {
                Text("Keine Listen gefunden.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(space.name)
        .task { await viewModel.loadSpaceContents(spaceID: space.id) }
    }

    private func listButton(_ list: ClickUpList) -> some View {
        Button {
            viewModel.selectInbox(list)
        } label: {
            HStack {
                Text(list.name)
                Spacer()
                if viewModel.settings.inboxListID == list.id {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }
}

/// Listen innerhalb eines Ordners.
private struct FolderListPicker: View {
    @ObservedObject var viewModel: SettingsViewModel
    let folder: ClickUpFolder

    var body: some View {
        List {
            if viewModel.folderLists.isEmpty {
                Text("Keine Listen in diesem Ordner.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.folderLists) { list in
                    Button {
                        viewModel.selectInbox(list)
                    } label: {
                        HStack {
                            Text(list.name)
                            Spacer()
                            if viewModel.settings.inboxListID == list.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .task { await viewModel.loadFolderLists(folderID: folder.id) }
    }
}
