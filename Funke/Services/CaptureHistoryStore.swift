import Foundation

/// Ein lokal protokollierter „Funke" — was erfasst wurde und wann.
/// Rein für die Capture-Oberfläche (Zähler „X Funken heute" + letzte Einträge);
/// die eigentliche Zustellung läuft unverändert über den `CaptureRouter`.
struct CapturedSpark: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let date: Date

    init(id: UUID = UUID(), text: String, date: Date) {
        self.id = id
        self.text = text
        self.date = date
    }
}

/// Lese-/Schreib-Schnittstelle des Capture-Verlaufs (testbar/mockbar).
protocol CaptureHistorying: Sendable {
    func record(text: String, date: Date) async
    func recent(limit: Int) async -> [CapturedSpark]
    func todayCount(now: Date) async -> Int
}

/// Persistenter Capture-Verlauf als JSON unter `<App Support>/Funke/captures.json`.
/// `actor` für serialisierte Zugriffe; gekappt auf die jüngsten Einträge, damit
/// die Datei nicht unbegrenzt wächst. Fehlende/kaputte Datei → leerer Verlauf
/// (kein stiller Crash, aber auch kein Datenverlust-Risiko für echte Captures —
/// dies ist reine Anzeige-Historie).
actor CaptureHistoryStore: CaptureHistorying {
    private let fileURL: URL
    private let directory: URL
    private let maxEntries: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cached: [CapturedSpark]?

    init(directory: URL = OfflineQueue.defaultDirectory, maxEntries: Int = 50) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("captures.json", isDirectory: false)
        self.maxEntries = maxEntries

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Hängt einen Eintrag vorne an (neueste zuerst) und kappt auf `maxEntries`.
    func record(text: String, date: Date) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = loaded()
        items.insert(CapturedSpark(text: trimmed, date: date), at: 0)
        if items.count > maxEntries { items = Array(items.prefix(maxEntries)) }
        persist(items)
    }

    func recent(limit: Int) async -> [CapturedSpark] {
        Array(loaded().prefix(max(0, limit)))
    }

    func todayCount(now: Date) async -> Int {
        let calendar = Calendar.current
        return loaded().filter { calendar.isDate($0.date, inSameDayAs: now) }.count
    }

    // MARK: - Persistence (best effort)

    private func loaded() -> [CapturedSpark] {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              !data.isEmpty,
              let items = try? decoder.decode([CapturedSpark].self, from: data) else {
            cached = []
            return []
        }
        cached = items
        return items
    }

    private func persist(_ items: [CapturedSpark]) {
        cached = items
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Anzeige-Historie: Schreibfehler werden bewusst geschluckt (kein Capture-Verlust).
        }
    }
}
