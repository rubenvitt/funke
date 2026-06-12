import Foundation

/// Persistente Offline-Queue für noch nicht gesendete Captures.
/// Speichert `[PendingCapture]` als JSON unter `directory/queue.json`.
/// Als `actor` ausgelegt, damit gleichzeitige Zugriffe serialisiert sind.
/// IO-Fehler werden sichtbar gemacht (kein stiller Verlust); eine fehlende
/// Datei gilt als leere Queue.
actor OfflineQueue: OfflineQueuing {
    private let directory: URL
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// In-Memory-Cache; `nil` bedeutet „noch nicht von Platte geladen".
    private var cached: [PendingCapture]?

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

    func enqueue(_ capture: PendingCapture) async throws {
        var items = try loaded()
        items.append(capture)
        try persist(items)
    }

    func all() async -> [PendingCapture] {
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
    private func loaded() throws -> [PendingCapture] {
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
        let items = try decoder.decode([PendingCapture].self, from: data)
        cached = items
        return items
    }

    private func persist(_ items: [PendingCapture]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(items)
        try data.write(to: fileURL, options: [.atomic])
        cached = items
    }
}
