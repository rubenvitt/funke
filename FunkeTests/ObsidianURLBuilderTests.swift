import XCTest
@testable import Funke

final class ObsidianURLBuilderTests: XCTestCase {

    // MARK: - Helfer

    /// Fixer Zeitpunkt für reproduzierbare Dateinamen: 2026-06-12 09:07 lokal.
    private func fixedDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 12
        components.hour = 9
        components.minute = 7
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func queryValue(_ url: URL, name: String) -> String?? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let items = components?.queryItems else { return .some(nil) }
        guard let item = items.first(where: { $0.name == name }) else { return .none }
        return .some(item.value)
    }

    private func hasFlag(_ url: URL, name: String) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.contains(where: { $0.name == name }) ?? false
    }

    // MARK: - inboxFile

    func testInboxFileBuildsNewURLWithSilentFlag() throws {
        let draft = NoteDraft(title: "Mein Titel", body: "Der Body", createdAt: fixedDate())
        let config = ObsidianConfig(vault: "MeinVault", inboxFolder: "Inbox", target: .inboxFile, useAdvancedURI: false)

        let url = try ObsidianURLBuilder.url(for: draft, config: config)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        XCTAssertEqual(components?.scheme, "obsidian")
        XCTAssertEqual(components?.host, "new")
        XCTAssertEqual(queryValue(url, name: "vault"), .some("MeinVault"))
        XCTAssertEqual(queryValue(url, name: "content"), .some("Der Body"))
        // file enthält den Inbox-Ordner als Unterpfad.
        XCTAssertEqual(queryValue(url, name: "file"), .some("Inbox/2026-06-12 0907 Mein Titel"))
        // silent als Presence-Flag (Name vorhanden, Wert nil).
        XCTAssertTrue(hasFlag(url, name: "silent"))
        XCTAssertEqual(queryValue(url, name: "silent"), .some(nil))
    }

    func testInboxFileWithoutFolderUsesBareFilename() throws {
        let draft = NoteDraft(title: "Notiz", body: "Inhalt", createdAt: fixedDate())
        let config = ObsidianConfig(vault: "V", inboxFolder: "", target: .inboxFile, useAdvancedURI: false)

        let url = try ObsidianURLBuilder.url(for: draft, config: config)

        XCTAssertEqual(queryValue(url, name: "file"), .some("2026-06-12 0907 Notiz"))
    }

    func testInboxFileSubfolderPathPreservedInFile() throws {
        let draft = NoteDraft(title: "X", body: "b", createdAt: fixedDate())
        let config = ObsidianConfig(vault: "V", inboxFolder: "Inbox/Sub", target: .inboxFile, useAdvancedURI: false)

        let url = try ObsidianURLBuilder.url(for: draft, config: config)

        XCTAssertEqual(queryValue(url, name: "file"), .some("Inbox/Sub/2026-06-12 0907 X"))
    }

    // MARK: - Dateiname / Bereinigung

    func testSanitizedFileNameStripsIllegalChars() {
        let name = ObsidianURLBuilder.sanitizedFileName(
            title: "a/b\\c:d#e^f[g]h|i?j",
            createdAt: fixedDate()
        )
        // Keine illegalen Zeichen mehr enthalten.
        for ch in "/\\:#^[]|?" {
            XCTAssertFalse(name.contains(ch), "Illegales Zeichen \(ch) nicht entfernt: \(name)")
        }
        XCTAssertTrue(name.hasPrefix("2026-06-12 0907 "))
    }

    func testSanitizedFileNameBlankTitleIsTimestampOnly() {
        let name = ObsidianURLBuilder.sanitizedFileName(title: "   ", createdAt: fixedDate())
        XCTAssertEqual(name, "2026-06-12 0907")
    }

    func testSanitizedFileNameCollapsesWhitespace() {
        let name = ObsidianURLBuilder.sanitizedFileName(title: "viel    Raum\tdazwischen", createdAt: fixedDate())
        XCTAssertEqual(name, "2026-06-12 0907 viel Raum dazwischen")
    }

    func testSanitizedFileNameTruncatesLongTitle() {
        let longTitle = String(repeating: "a", count: 200)
        let name = ObsidianURLBuilder.sanitizedFileName(title: longTitle, createdAt: fixedDate())
        // Präfix (15) + Leerzeichen (1) + max. 80 Titelzeichen.
        XCTAssertLessThanOrEqual(name.count, 15 + 1 + 80)
    }

    // MARK: - Fehlerfälle

    func testBlankVaultThrowsMissingVault() {
        let draft = NoteDraft(title: "T", body: "B", createdAt: fixedDate())
        let config = ObsidianConfig(vault: "   ", inboxFolder: "Inbox", target: .inboxFile, useAdvancedURI: false)

        XCTAssertThrowsError(try ObsidianURLBuilder.url(for: draft, config: config)) { error in
            XCTAssertEqual(error as? ObsidianError, .missingVault)
        }
    }

    // MARK: - dailyNote / adv-uri

    func testDailyNoteWithAdvancedURIBuildsAdvURIAppend() throws {
        let draft = NoteDraft(title: "egal", body: "Tagesnotiz-Inhalt", createdAt: fixedDate())
        let config = ObsidianConfig(vault: "V", inboxFolder: "Inbox", target: .dailyNote, useAdvancedURI: true)

        let url = try ObsidianURLBuilder.url(for: draft, config: config)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        XCTAssertEqual(components?.scheme, "obsidian")
        XCTAssertEqual(components?.host, "adv-uri")
        XCTAssertEqual(queryValue(url, name: "vault"), .some("V"))
        XCTAssertEqual(queryValue(url, name: "daily"), .some("true"))
        XCTAssertEqual(queryValue(url, name: "mode"), .some("append"))
        XCTAssertEqual(queryValue(url, name: "data"), .some("Tagesnotiz-Inhalt"))
        XCTAssertEqual(queryValue(url, name: "openmode"), .some("silent"))
    }

    func testDailyNoteWithoutAdvancedURIFallsBackToInboxFile() throws {
        let draft = NoteDraft(title: "Fallback", body: "Body", createdAt: fixedDate())
        let config = ObsidianConfig(vault: "V", inboxFolder: "Inbox", target: .dailyNote, useAdvancedURI: false)

        let url = try ObsidianURLBuilder.url(for: draft, config: config)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // Fallback auf obsidian://new (inboxFile).
        XCTAssertEqual(components?.host, "new")
        XCTAssertEqual(queryValue(url, name: "file"), .some("Inbox/2026-06-12 0907 Fallback"))
        XCTAssertTrue(hasFlag(url, name: "silent"))
    }
}
