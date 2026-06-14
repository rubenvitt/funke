import Foundation

/// Wohin eine Notiz in Obsidian geschrieben wird.
enum ObsidianNoteTarget: String, Codable, Sendable, CaseIterable {
    /// Neue Markdown-Datei im konfigurierten Inbox-Ordner (`obsidian://new`).
    case inboxFile
    /// Anhängen an die heutige Tagesnotiz (benötigt das Advanced-URI-Plugin).
    case dailyNote
}

/// Nicht-geheime Obsidian-Konfiguration aus den App-Einstellungen.
struct ObsidianConfig: Equatable, Sendable {
    /// Name des Obsidian-Vaults (Pflicht — leer ⇒ Fehler).
    var vault: String
    /// Vault-relativer Ordner für neue Notizen (z. B. „Inbox"; leer ⇒ Vault-Wurzel).
    var inboxFolder: String
    /// Ziel der Notiz.
    var target: ObsidianNoteTarget
    /// Nur relevant für `dailyNote`: per Advanced-URI-Plugin an die Tagesnotiz anhängen.
    var useAdvancedURI: Bool
}

/// Baut `obsidian://`-URLs für Notiz-Captures. Rein/testbar — kein UIKit, kein Öffnen.
///
/// Grundsatz: `URLComponents` übernimmt das Percent-Encoding der Query-Werte;
/// ein literaler `/` im `file`-Parameter ist als Ordnertrenner erlaubt.
enum ObsidianURLBuilder {
    /// Erlaubte Maximallänge des Titel-Anteils im Dateinamen (Zeichen).
    private static let maxTitleLength = 80

    /// Baut die Ziel-URL für einen Notiz-Entwurf.
    ///
    /// - `inboxFile` → `obsidian://new` mit `vault`, `file`, `content` und Flag `silent`.
    /// - `dailyNote` + `useAdvancedURI` → `obsidian://adv-uri` (anhängen an Tagesnotiz).
    /// - `dailyNote` ohne `useAdvancedURI` → fällt auf `inboxFile` zurück.
    ///
    /// Wirft `ObsidianError.missingVault`, wenn der Vault-Name leer ist, bzw.
    /// `ObsidianError.invalidURL`, falls `URLComponents` keine URL liefert.
    static func url(for draft: NoteDraft, config: ObsidianConfig) throws -> URL {
        let vault = config.vault.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vault.isEmpty else { throw ObsidianError.missingVault }

        if config.target == .dailyNote && config.useAdvancedURI {
            return try dailyNoteURL(for: draft, vault: vault)
        }
        return try inboxFileURL(for: draft, vault: vault, inboxFolder: config.inboxFolder)
    }

    // MARK: - Varianten

    /// `obsidian://new`: neue Datei mit `silent`-Flag (Notiz nicht öffnen).
    private static func inboxFileURL(for draft: NoteDraft, vault: String, inboxFolder: String) throws -> URL {
        let name = sanitizedFileName(title: draft.title, createdAt: draft.createdAt)
        let folder = inboxFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = folder.isEmpty ? name : "\(folder)/\(name)"

        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "new"
        components.queryItems = [
            URLQueryItem(name: "vault", value: vault),
            URLQueryItem(name: "file", value: file),
            URLQueryItem(name: "content", value: draft.body),
            // Presence-Flag: Notiz anlegen, aber nicht im Vordergrund öffnen.
            URLQueryItem(name: "silent", value: nil)
        ]

        guard let url = components.url else { throw ObsidianError.invalidURL }
        return url
    }

    /// `obsidian://adv-uri`: an die heutige Tagesnotiz anhängen (Advanced-URI-Plugin).
    private static func dailyNoteURL(for draft: NoteDraft, vault: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "adv-uri"
        components.queryItems = [
            URLQueryItem(name: "vault", value: vault),
            URLQueryItem(name: "daily", value: "true"),
            URLQueryItem(name: "mode", value: "append"),
            URLQueryItem(name: "data", value: draft.body),
            URLQueryItem(name: "openmode", value: "silent")
        ]

        guard let url = components.url else { throw ObsidianError.invalidURL }
        return url
    }

    // MARK: - Dateiname

    /// Baut einen sicheren, vault-relativen Dateinamen (ohne `.md`, das impliziert Obsidian):
    /// Präfix `yyyy-MM-dd HHmm ` plus dem bereinigten Titel.
    /// Bei leerem Titel bleibt nur der Zeitstempel.
    static func sanitizedFileName(title: String, createdAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let prefix = formatter.string(from: createdAt)

        let cleaned = cleanTitle(title)
        return cleaned.isEmpty ? prefix : "\(prefix) \(cleaned)"
    }

    /// Entfernt dateisystem-/Obsidian-illegale Zeichen, kollabiert Whitespace und kürzt.
    private static func cleanTitle(_ title: String) -> String {
        // Illegale Zeichen (`/ \ : # ^ [ ] | ?`) plus Steuerzeichen entfernen.
        let illegal = CharacterSet(charactersIn: "/\\:#^[]|?").union(.controlCharacters)
        let stripped = title.components(separatedBy: illegal).joined(separator: " ")

        // Whitespace kollabieren und trimmen.
        let collapsed = stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard collapsed.count > maxTitleLength else { return collapsed }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: maxTitleLength)
        return String(collapsed[collapsed.startIndex..<endIndex])
            .trimmingCharacters(in: .whitespaces)
    }
}
