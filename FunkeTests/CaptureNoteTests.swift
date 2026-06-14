import XCTest
@testable import Funke

@MainActor
final class CaptureNoteTests: XCTestCase {

    // MARK: - Erfolg

    func testNoteSuccessClearsTextAndShowsSuccessBanner() async {
        let opener = MockOpener(result: true)
        let settings = makeSettings(vault: "MeinVault")
        var haptics: [HapticFeedback] = []
        let vm = CaptureViewModel(
            clickUp: MockClickUp(),
            enrichment: MockEnrichment(),
            settings: settings,
            queue: MockQueue(),
            transcriber: nil,
            onHaptic: { haptics.append($0) },
            openURL: opener.open
        )
        vm.mode = .note
        vm.text = "Meine Notiz"

        await vm.capture()

        XCTAssertEqual(vm.text, "", "Text wird nur bei Erfolg geleert")
        XCTAssertEqual(vm.banner, .success("Notiz an Obsidian gesendet."))
        XCTAssertTrue(haptics.contains(.success))
        // URL wurde gebaut und an den Opener übergeben.
        XCTAssertNotNil(opener.capturedURL)
        XCTAssertEqual(opener.capturedURL?.scheme, "obsidian")
    }

    // MARK: - Fehler beim Öffnen (Text bleibt erhalten)

    func testNoteOpenFailureKeepsTextAndShowsFailureBanner() async {
        let opener = MockOpener(result: false)
        let settings = makeSettings(vault: "MeinVault")
        var haptics: [HapticFeedback] = []
        let vm = CaptureViewModel(
            clickUp: MockClickUp(),
            enrichment: MockEnrichment(),
            settings: settings,
            queue: MockQueue(),
            transcriber: nil,
            onHaptic: { haptics.append($0) },
            openURL: opener.open
        )
        vm.mode = .note
        vm.text = "Wichtige Notiz"

        await vm.capture()

        XCTAssertEqual(vm.text, "Wichtige Notiz", "Text MUSS bei Fehler erhalten bleiben (kein Verlust)")
        if case .failure = vm.banner {} else {
            XCTFail("Erwartete Fehler-Banner, war: \(String(describing: vm.banner))")
        }
        XCTAssertTrue(haptics.contains(.error))
        XCTAssertNotNil(opener.capturedURL, "Opener wurde aufgerufen")
    }

    // MARK: - Fehlender Vault (Opener wird nicht aufgerufen)

    func testNoteMissingVaultShowsFailureAndDoesNotOpen() async {
        let opener = MockOpener(result: true)
        let settings = makeSettings(vault: "")
        var haptics: [HapticFeedback] = []
        let vm = CaptureViewModel(
            clickUp: MockClickUp(),
            enrichment: MockEnrichment(),
            settings: settings,
            queue: MockQueue(),
            transcriber: nil,
            onHaptic: { haptics.append($0) },
            openURL: opener.open
        )
        vm.mode = .note
        vm.text = "Notiz ohne Vault"

        await vm.capture()

        XCTAssertEqual(vm.text, "Notiz ohne Vault", "Text bleibt erhalten")
        if case .failure = vm.banner {} else {
            XCTFail("Erwartete Fehler-Banner bei fehlendem Vault")
        }
        XCTAssertTrue(haptics.contains(.error))
        XCTAssertNil(opener.capturedURL, "Ohne Vault darf der Opener NICHT aufgerufen werden")
    }

    // MARK: - KI an: Notiz „direkt mit KI" bereinigt

    func testNoteWithEnrichmentUsesAITitleAndBody() async throws {
        let opener = MockOpener(result: true)
        let settings = makeSettings(vault: "MeinVault")
        settings.enrichmentEnabled = true
        let enrichment = MockEnrichment()
        enrichment.noteResult = NoteSuggestion(title: "Sauberer Titel", body: "Bereinigter Body")
        let vm = CaptureViewModel(
            clickUp: MockClickUp(),
            enrichment: enrichment,
            settings: settings,
            queue: MockQueue(),
            transcriber: nil,
            openURL: opener.open
        )
        vm.mode = .note
        vm.text = "roh diktierter text äh also"

        await vm.capture()

        XCTAssertEqual(vm.text, "", "Bei Erfolg wird der Text geleert")
        XCTAssertEqual(vm.banner, .success("Notiz an Obsidian gesendet."))

        // Die geöffnete URL muss den KI-Body als content tragen und den KI-Titel
        // im Dateinamen (file).
        let url = try XCTUnwrap(opener.capturedURL)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let content = components?.queryItems?.first { $0.name == "content" }?.value
        XCTAssertEqual(content, "Bereinigter Body")
        let file = components?.queryItems?.first { $0.name == "file" }?.value ?? ""
        XCTAssertTrue(file.contains("Sauberer Titel"), "Dateiname sollte den KI-Titel enthalten, war: \(file)")
    }

    func testNoteWithEnrichmentFailureSendsRawNote() async throws {
        let opener = MockOpener(result: true)
        let settings = makeSettings(vault: "MeinVault")
        settings.enrichmentEnabled = true
        let enrichment = MockEnrichment()
        enrichment.noteError = EnrichmentError.transport("KI weg")
        let vm = CaptureViewModel(
            clickUp: MockClickUp(),
            enrichment: enrichment,
            settings: settings,
            queue: MockQueue(),
            transcriber: nil,
            openURL: opener.open
        )
        vm.mode = .note
        vm.text = "Wichtige Rohnotiz"

        await vm.capture()

        // KI-Fehler ist nie blockierend: Rohnotiz wird gesendet, Text geleert.
        XCTAssertEqual(vm.text, "", "Bei erfolgreichem Öffnen wird der Text geleert")
        XCTAssertEqual(vm.banner, .success("Notiz an Obsidian gesendet."))
        let url = try XCTUnwrap(opener.capturedURL)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let content = components?.queryItems?.first { $0.name == "content" }?.value
        XCTAssertEqual(content, "Wichtige Rohnotiz", "Rohtext muss als content gesendet werden")
    }

    // MARK: - Helpers

    private func makeSettings(vault: String) -> AppSettings {
        let defaults = UserDefaults(suiteName: "test-note-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.obsidianVault = vault
        settings.obsidianInboxFolder = "Inbox"
        settings.obsidianNoteTarget = .inboxFile
        settings.obsidianUseAdvancedURI = false
        return settings
    }
}

// MARK: - Mocks

/// Fängt die übergebene URL ab und liefert ein konfigurierbares Ergebnis.
private final class MockOpener: @unchecked Sendable {
    private let result: Bool
    private(set) var capturedURL: URL?

    init(result: Bool) {
        self.result = result
    }

    @MainActor
    func open(_ url: URL) async -> Bool {
        capturedURL = url
        return result
    }
}

private final class MockClickUp: ClickUpClienting, @unchecked Sendable {
    func authorizedUser() async throws -> ClickUpUser { ClickUpUser(id: 1, username: "t") }
    func teams() async throws -> [ClickUpTeam] { [] }
    func spaces(teamID: String) async throws -> [ClickUpSpace] { [] }
    func folders(spaceID: String) async throws -> [ClickUpFolder] { [] }
    func folderlessLists(spaceID: String) async throws -> [ClickUpList] { [] }
    func folderLists(folderID: String) async throws -> [ClickUpList] { [] }
    func createTask(listID: String, name: String, markdownDescription: String?, priority: Priority?) async throws {}
    func todayTasks(teamID: String, assigneeID: Int, now: Date) async throws -> [TodayTask] { [] }
    func listStatuses(listID: String) async throws -> [ClickUpStatusInfo] { [] }
    func setStatus(taskID: String, status: String) async throws {}
}

private final class MockEnrichment: EnrichmentServicing, @unchecked Sendable {
    var available: ProviderAvailability = .available
    var noteResult: NoteSuggestion = NoteSuggestion(title: "x", body: "x")
    var noteError: Error?

    func availability(for kind: EnrichmentProviderKind) async -> ProviderAvailability { available }

    func enrich(_ rawText: String, using kind: EnrichmentProviderKind, openRouterModel: String) async throws -> EnrichmentSuggestion {
        EnrichmentSuggestion(title: "x")
    }

    func enrichNote(_ rawText: String, using kind: EnrichmentProviderKind, openRouterModel: String) async throws -> NoteSuggestion {
        if let noteError { throw noteError }
        return noteResult
    }
}

private actor MockQueue: OfflineQueuing {
    private var items: [PendingCapture] = []
    func enqueue(_ capture: PendingCapture) async throws { items.append(capture) }
    func all() async -> [PendingCapture] { items }
    func remove(id: UUID) async throws { items.removeAll { $0.id == id } }
    func isEmpty() async -> Bool { items.isEmpty }
}
