import Foundation

/// Schreibt Notizen direkt ins lokale Vault-Verzeichnis (macOS). Der Mac ist
/// selbst ein Obsidian-Sync-Client; eine neue `.md` im Vault-Ordner wird von
/// Obsidian Sync verteilt — kein Netz nötig, kein Server-Umweg.
///
/// `vaultRoot` wird vom Composition-Root aufgelöst (Security-Scoped Bookmark,
/// einmalige `NSOpenPanel`-Wahl); der Sink selbst ist plattformneutral/testbar.
/// Schreibt atomar (`temp + rename`) und legt den Zielordner bei Bedarf an.
struct LocalFileNoteSink: NoteSink {
    let vaultRoot: URL
    let folder: String
    var timeZone: TimeZone = .current

    func write(_ draft: NoteDraft) async throws {
        let name = NoteFileName.make(title: draft.title, createdAt: draft.createdAt, timeZone: timeZone)
        let directory = folder.trimmingCharacters(in: .whitespaces).isEmpty
            ? vaultRoot
            : vaultRoot.appendingPathComponent(folder, isDirectory: true)
        let fileURL = directory.appendingPathComponent("\(name).md", isDirectory: false)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(draft.body.utf8).write(to: fileURL, options: [.atomic])
        } catch {
            throw NoteSinkError.fileSystem(error.localizedDescription)
        }
    }
}
