import Foundation

/// Persistente Offline-Queue für noch nicht gesendete Captures (Tasks + Notizen).
/// Speichert `[PendingItem]` als JSON unter `directory/queue.json`.
/// Als `actor` ausgelegt, damit gleichzeitige Zugriffe serialisiert sind.
/// IO-Fehler werden sichtbar gemacht (kein stiller Verlust); eine fehlende
/// Datei gilt als leere Queue. Alte reine `[PendingCapture]`-Dateien (vor v2)
/// werden beim ersten Laden transparent zu `.task`-Items migriert.
actor OfflineQueue: OfflineQueuing {
    private let directory: URL
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// In-Memory-Cache; `nil` bedeutet „noch nicht von Platte geladen".
    private var cached: [PendingItem]?

    init(directory: URL = OfflineQueue.defaultDirectory) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("queue.json", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Standardverzeichnis: `<Application Support>/Funke`.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Funke", isDirectory: true)
    }

    // MARK: - OfflineQueuing

    func enqueue(_ item: PendingItem) async throws {
        var items = try loaded()
        items.append(item)
        try persist(items)
    }

    func all() async -> [PendingItem] {
        // `all()` ist nicht-werfend (Protokoll): ein Lese-IO-Fehler darf hier
        // nicht crashen. Im Fehlerfall liefern wir den bekannten Cache bzw. leer.
        if let cached { return cached }
        do {
            return try loaded()
        } catch {
            return []
        }
    }

    func remove(id: UUID) async throws {
        var items = try loaded()
        items.removeAll { $0.id == id }
        try persist(items)
    }

    func isEmpty() async -> Bool {
        await all().isEmpty
    }

    // MARK: - Persistence

    /// Lädt die Queue lazy von Platte. Fehlende Datei → leere Queue.
    /// Migration: schlägt das neue `[PendingItem]`-Format fehl, wird die alte
    /// reine `[PendingCapture]`-Datei gelesen und als `.task`-Items übernommen.
    private func loaded() throws -> [PendingItem] {
        if let cached { return cached }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cached = []
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            cached = []
            return []
        }

        if let items = try? decoder.decode([PendingItem].self, from: data) {
            cached = items
            return items
        }

        // Migration vom Vor-v2-Format: reines [PendingCapture].
        let legacy = try decoder.decode([PendingCapture].self, from: data)
        let migrated = legacy.map { PendingItem.task($0) }
        cached = migrated
        try persist(migrated)
        return migrated
    }

    private func persist(_ items: [PendingItem]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(items)
        try data.write(to: fileURL, options: [.atomic])
        cached = items
    }
}
