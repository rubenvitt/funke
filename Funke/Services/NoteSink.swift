import Foundation

/// Schreibt eine Notiz in den Obsidian-Vault. Ersetzt den alten
/// `obsidian://`-URL-Weg (App-Wechsel/Flow-Bruch). Zwei Implementierungen:
/// `RelayNoteSink` (HTTPS an den Server, iOS/Watch-Relay-Ziel) und
/// `LocalFileNoteSink` (direkt ins lokale Vault-Verzeichnis, macOS).
/// Protokollbasiert, damit `CaptureRouter`/ViewModel ohne IO testbar bleiben.
protocol NoteSink: Sendable {
    /// Schreibt den Entwurf. Wirft `NoteSinkError`; `.transport` signalisiert dem
    /// Aufrufer „später erneut versuchen" (Offline-Queue), nie stiller Verlust.
    func write(_ draft: NoteDraft) async throws
}
