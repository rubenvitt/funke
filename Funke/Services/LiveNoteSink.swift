import Foundation

/// `NoteSink`, der bei **jedem** Schreibvorgang die aktuelle Zielkonfiguration
/// auflöst (Relay-URL/Token bzw. lokales Vault). So greifen Settings-Änderungen
/// sofort, ohne den Composition-Root neu zu bauen. Ist nichts konfiguriert,
/// wirft er `NoteSinkError.notConfigured` (kein stiller Verlust).
struct LiveNoteSink: NoteSink {
    let resolve: @Sendable () async -> NoteSink?

    func write(_ draft: NoteDraft) async throws {
        guard let sink = await resolve() else {
            throw NoteSinkError.notConfigured("Notiz-Ziel nicht eingerichtet (Relay-URL/Token bzw. Vault-Ordner).")
        }
        try await sink.write(draft)
    }
}
