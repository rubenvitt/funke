import Foundation

/// Erzeugt UUIDv7-IDs im kanonischen Zunder-Format (36 Zeichen, klein,
/// mit Bindestrichen). Die ersten 48 Bit sind Unix-Millisekunden – IDs sind
/// damit grob zeitlich sortiert, wie es Zunder für Client-IDs vorsieht.
enum UUIDv7 {
    static func generate(at date: Date = Date()) -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(at: date, using: &generator)
    }

    static func generate<R: RandomNumberGenerator>(at date: Date, using generator: inout R) -> String {
        let millis = UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded(.down)))
        var bytes = [UInt8](repeating: 0, count: 16)
        // 48 Bit Zeitstempel (big endian).
        for index in 0..<6 {
            bytes[index] = UInt8(truncatingIfNeeded: millis >> (8 * UInt64(5 - index)))
        }
        // 80 Bit Zufall.
        for index in 6..<16 {
            bytes[index] = UInt8.random(in: .min ... .max, using: &generator)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70   // Version 7
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // Variante 10xx (RFC 9562)

        let hex = bytes.map { byte -> String in
            let digits = String(byte, radix: 16)
            return digits.count == 1 ? "0" + digits : digits
        }
        return [hex[0..<4], hex[4..<6], hex[6..<8], hex[8..<10], hex[10..<16]]
            .map { $0.joined() }
            .joined(separator: "-")
    }
}

/// Knoten-ID dieser Funke-Installation für HLCs und `client_id`
/// (`funke-` + 8 Hex-Zeichen, einmalig erzeugt und in UserDefaults gehalten).
/// Muss dem Zunder-Muster `[a-z0-9-]{1,36}` genügen.
enum ZunderNodeID {
    static let defaultsKey = "zunderNodeID"

    static func load(from defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: defaultsKey), isValid(existing) {
            return existing
        }
        let created = make()
        defaults.set(created, forKey: defaultsKey)
        return created
    }

    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        let suffix = (0..<8).map { _ in String(Int.random(in: 0..<16, using: &generator), radix: 16) }.joined()
        return "funke-" + suffix
    }

    static func isValid(_ node: String) -> Bool {
        guard (1...36).contains(node.count) else { return false }
        return node.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (97...122).contains(value)   // a–z
                || (48...57).contains(value)     // 0–9
                || value == 45                   // -
        }
    }
}

/// Hybrid Logical Clock nach Zunder-Vertrag (Abschnitt 2.2):
/// `"<wall_ms 13-stellig>:<counter 5-stellig>:<node>"`.
///
/// `next` liefert streng monoton steigende Werte (`max(physisch, letzter)`,
/// gleicher `wall_ms` → Zähler + 1, Überlauf → `wall_ms` + 1). Über `notBefore`
/// lässt sich die Uhr – wie `receive` – über einen bekannten Server-Stand heben.
/// Prozessweit geteilt (`shared`), damit parallele Router-Instanzen
/// (App, App-Intent, Watch-Relay) keine identischen HLCs erzeugen.
final class HybridLogicalClock: @unchecked Sendable {
    static let shared = HybridLogicalClock()

    private static let maxCounter = 99_999

    private let lock = NSLock()
    private var lastWallMs: UInt64 = 0
    private var lastCounter: Int = 0

    init() {}

    /// Nächster Zeitstempel als `(wall_ms, counter)`.
    func next(now: Date, notBefore: Date? = nil) -> (wallMs: UInt64, counter: Int) {
        let physical = Self.millis(now)
        let floor = notBefore.map { Self.millis($0) + 1 } ?? 0
        lock.lock()
        defer { lock.unlock() }

        let candidate = max(physical, floor)
        if candidate > lastWallMs {
            lastWallMs = candidate
            lastCounter = 0
        } else if lastCounter >= Self.maxCounter {
            lastWallMs += 1
            lastCounter = 0
        } else {
            lastCounter += 1
        }
        return (lastWallMs, lastCounter)
    }

    /// Formatiert einen HLC-String mit fester Breite.
    static func format(wallMs: UInt64, counter: Int, node: String) -> String {
        let wall = String(wallMs)
        let paddedWall = String(repeating: "0", count: max(0, 13 - wall.count)) + wall
        let count = String(counter)
        let paddedCounter = String(repeating: "0", count: max(0, 5 - count.count)) + count
        return "\(paddedWall):\(paddedCounter):\(node)"
    }

    private static func millis(_ date: Date) -> UInt64 {
        UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded(.down)))
    }
}

/// Baut Zunder-Operationen für Funke: neue Inbox-Aufgaben und Statuswechsel.
///
/// Rein und testbar: Uhr, Zeitquelle und ID-Erzeugung sind injizierbar.
/// Erzeugte Entwürfe werden vom Aufrufer persistiert, bevor sie gesendet
/// werden – das macht das Nachsenden idempotent.
struct ZunderOpFactory: Sendable {
    /// Höchstlänge eines Aufgaben-Titels laut Zunder-Vertrag.
    static let maxTitleLength = 500

    let node: String
    private let clock: HybridLogicalClock
    private let now: @Sendable () -> Date
    private let makeID: @Sendable (Date) -> String

    init(
        node: String,
        clock: HybridLogicalClock = .shared,
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable (Date) -> String = { UUIDv7.generate(at: $0) }
    ) {
        self.node = node
        self.clock = clock
        self.now = now
        self.makeID = makeID
    }

    /// Neue Aufgabe in der Inbox: `title`, `location` (explizit Inbox) und –
    /// nur wenn nicht leer – `description`. Überlange Titel werden gekürzt;
    /// der volle Text wandert dann in die Beschreibung (nichts geht verloren).
    func makeTaskDraft(title rawTitle: String, description rawDescription: String?) -> ZunderTaskDraft {
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var description = rawDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if title.count > Self.maxTitleLength {
            let full = title
            title = String(full.prefix(Self.maxTitleLength - 1)) + "…"
            description = description.isEmpty ? full : full + "\n\n" + description
        }

        let date = now()
        let taskID = makeID(date)
        var fields: [(String, JSONValue)] = [
            ("title", .string(title)),
            ("location", .object(["kind": .string("inbox")])),
        ]
        if !description.isEmpty {
            fields.append(("description", .string(description)))
        }

        let ops = fields.map { field, value in
            makeOp(entityID: taskID, field: field, value: value, at: date, notBefore: nil)
        }
        return ZunderTaskDraft(taskID: taskID, ops: ops)
    }

    /// Statuswechsel einer bestehenden Aufgabe (z. B. `done`). `notBefore` hebt
    /// den HLC über den bekannten Server-Stand (`updated_at`), damit die
    /// Änderung den Last-Writer-Wins-Vergleich auch bei Uhrenabweichung gewinnt.
    func makeStatusOp(taskID: String, status: String, notBefore: Date?) -> ZunderOp {
        makeOp(entityID: taskID, field: "status", value: .string(status), at: now(), notBefore: notBefore)
    }

    private func makeOp(entityID: String, field: String, value: JSONValue, at date: Date, notBefore: Date?) -> ZunderOp {
        let tick = clock.next(now: date, notBefore: notBefore)
        return ZunderOp(
            opID: makeID(date),
            entity: "task",
            entityID: entityID,
            field: field,
            value: value,
            hlc: HybridLogicalClock.format(wallMs: tick.wallMs, counter: tick.counter, node: node)
        )
    }
}
