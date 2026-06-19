import SwiftUI

/// Einstellungen: ClickUp-Verbindung, Inbox-Auswahl und KI-Provider — im Glut-Look.
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
                timelineSection
                phoenixSection
                aiSection
                relaySection
                footerSection
            }
            // Glut-Theming: System-Form-Hintergrund weg, warme Fläche drunter.
            .scrollContentBackground(.hidden)
            .background(FunkeTheme.background)
            .tint(FunkeTheme.accent)
            .navigationTitle("Einstellungen")
            .task { await viewModel.loadPhoenix() }
            .task { await viewModel.loadCalendars() }
        }
    }

    // MARK: - ClickUp

    private var clickUpSection: some View {
        Section(header: Text("ClickUp").funkeSectionLabel()) {
            SecureField("Personal Token (pk_…)", text: $viewModel.clickUpToken)
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
            .foregroundStyle(FunkeTheme.accent)
            .disabled(viewModel.isTestingConnection)

            statusRow(viewModel.connectionStatus)
        }
    }

    // MARK: - Workspace

    private var workspaceSection: some View {
        Section(header: Text("Workspace").funkeSectionLabel()) {
            if viewModel.teams.isEmpty {
                Text("Nach erfolgreichem Verbindungstest erscheinen hier deine Workspaces.")
                    .font(.footnote)
                    .foregroundStyle(FunkeTheme.dim)
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
                    .foregroundStyle(FunkeTheme.red)
            }
        }
    }

    // MARK: - Inbox

    private var inboxSection: some View {
        Section(header: Text("Inbox-Liste").funkeSectionLabel()) {
            if let name = settings.inboxListName {
                Label(name, systemImage: "tray")
                    .foregroundStyle(FunkeTheme.text)
            } else {
                Text("Noch keine Inbox gewählt.")
                    .foregroundStyle(FunkeTheme.dim)
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
                .foregroundStyle(FunkeTheme.accent)
            }
        }
    }

    // MARK: - Tages-Timeline (Timeblocking-Kalender)

    private var timelineSection: some View {
        Section(
            header: Text("Tages-Timeline").funkeSectionLabel(),
            footer: Text("Wähle den Kalender, dessen Termine auf der Heute-Timeline erscheinen.")
                .font(.footnote)
                .foregroundStyle(FunkeTheme.dim)
        ) {
            if viewModel.calendars.isEmpty {
                Text("Keine Kalender verfügbar. Erlaube den Kalenderzugriff in den iOS-Einstellungen.")
                    .font(.footnote)
                    .foregroundStyle(FunkeTheme.dim)
            } else {
                Picker("Timeblocking-Kalender", selection: calendarBinding) {
                    Text("Alle Kalender").tag(String?.none)
                    ForEach(viewModel.calendars) { cal in
                        Text(cal.title).tag(Optional(cal.id))
                    }
                }
            }
        }
    }

    // MARK: - Feuersturm · 12 Wochen (Phönix-Progression)

    private var phoenixSection: some View {
        Section(header: phoenixHeader) {
            if viewModel.isLoadingPhoenix {
                HStack {
                    ProgressView()
                    Text("Lade Feuersturm…")
                        .font(.footnote)
                        .foregroundStyle(FunkeTheme.dim)
                }
            }

            // Aktiver Zustand der Progression (kein Schalter): Woche X von N.
            if let feuersturm = viewModel.phoenix?.feuersturm {
                Text("\(feuersturm.title) · Woche \(feuersturm.weekIndex) von \(feuersturm.totalWeeks)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FunkeTheme.text)
            }

            // Ziele: Titel + Status, darunter optionaler Fortschrittsbalken.
            if let goals = viewModel.phoenix?.goals {
                ForEach(goals) { goal in
                    goalRow(goal)
                }
            }

            if let error = viewModel.phoenixError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(FunkeTheme.red)
            }
        }
    }

    // Header mit Flammen-Symbol in Akzent.
    private var phoenixHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(FunkeTheme.accent)
            Text("Feuersturm · 12 Wochen")
        }
        .funkeSectionLabel()
    }

    @ViewBuilder
    private func goalRow(_ goal: PhoenixGoal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title)
                    .foregroundStyle(FunkeTheme.text)
                Spacer()
                Text(goal.statusName)
                    .font(.footnote)
                    .foregroundStyle(FunkeTheme.dim)
            }

            if let progress = goal.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(FunkeTheme.line)
                        Capsule()
                            .fill(FunkeTheme.accent)
                            .frame(width: geo.size.width * max(0, min(1, progress)))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - KI

    private var aiSection: some View {
        Section(header: Text("KI-Veredelung").funkeSectionLabel()) {
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
                            viewModel.providerAvailability?.isAvailable == true ? FunkeTheme.positive : FunkeTheme.dim
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
                    .foregroundStyle(FunkeTheme.accent)
                statusRow(viewModel.keyStatus)
            }
        }
        .task { await viewModel.checkProviderAvailability() }
    }

    // MARK: - Relay (Notiz-Transport)

    private var relaySection: some View {
        Section(header: Text("Notiz-Transport (Relay)").funkeSectionLabel()) {
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
                    .foregroundStyle(settings.vaultBookmark == nil ? FunkeTheme.dim : FunkeTheme.positive)
            }
            Button("Vault-Ordner wählen…") {
                if let bookmark = MacVaultAccess.pickVaultBookmark() {
                    settings.vaultBookmark = bookmark
                }
            }
            .foregroundStyle(FunkeTheme.accent)
            #endif

            Button("Token speichern") { viewModel.saveRelayToken() }
                .foregroundStyle(FunkeTheme.accent)

            Button {
                Task { await viewModel.testRelay() }
            } label: {
                HStack {
                    Text("Relay testen")
                    Spacer()
                    if viewModel.isTestingRelay { ProgressView() }
                }
            }
            .foregroundStyle(FunkeTheme.accent)
            .disabled(viewModel.isTestingRelay)

            statusRow(viewModel.relayStatus)

            Text("Notizen gehen an deinen Relay-Server (obsidian-headless); Obsidian Sync verteilt sie. Auf dem Mac kann Funke stattdessen direkt ins lokale Vault schreiben.")
                .font(.footnote)
                .foregroundStyle(FunkeTheme.dim)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        Section {
            Text("Funke · v0.3 · Erschaffen → Loslassen → Neuerschaffen")
                .font(.system(size: 12))
                .foregroundStyle(FunkeTheme.dim)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
        }
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

    private var calendarBinding: Binding<String?> {
        Binding(
            get: { settings.timeblockCalendarID },
            set: { viewModel.selectTimeblockCalendar($0) }
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
                    .foregroundStyle(FunkeTheme.positive)
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(FunkeTheme.red)
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
