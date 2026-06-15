import Foundation

/// Baut sichere, vault-relative Dateinamen für Obsidian-Notizen (ohne `.md`).
/// Rein/testbar — kein IO, keine Plattform-Abhängigkeit. Geteilt von allen
/// `NoteSink`-Implementierungen (Server-Relay wie lokales Dateisystem).
///
/// Format: `yyyy-MM-dd HHmm ` plus dem bereinigten Titel; bei leerem Titel
/// bleibt nur der Zeitstempel. Illegale Zeichen werden entfernt, Whitespace
/// kollabiert, der Titel auf eine Maximallänge gekürzt.
enum NoteFileName {
    /// Erlaubte Maximallänge des Titel-Anteils (Zeichen).
    static let maxTitleLength = 80

    /// Vollständiger Dateiname: Zeitstempel-Präfix + bereinigter Titel.
    /// `timeZone` ist injizierbar (Default lokal), damit der Präfix testbar ist.
    static func make(title: String, createdAt: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let prefix = formatter.string(from: createdAt)

        let cleaned = clean(title)
        return cleaned.isEmpty ? prefix : "\(prefix) \(cleaned)"
    }

    /// Entfernt dateisystem-/Obsidian-illegale Zeichen (`/ \ : # ^ [ ] | ?` plus
    /// Steuerzeichen), kollabiert Whitespace und kürzt auf `maxTitleLength`.
    static func clean(_ title: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:#^[]|?").union(.controlCharacters)
        let stripped = title.components(separatedBy: illegal).joined(separator: " ")

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
