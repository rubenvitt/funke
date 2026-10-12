import Foundation

/// Der zum API-Token gehörende Zunder-Nutzer (`GET /api/me`).
/// Name und E-Mail können fehlen, solange sich der Besitzer noch nie per
/// OIDC angemeldet hat (z. B. nach einem Import per Bootstrap-Token).
struct ZunderUser: Equatable, Sendable {
    let name: String?
    let email: String?

    /// Lesbare Kurzform für „Verbunden als …".
    var displayName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (trimmedName.isEmpty, trimmedEmail.isEmpty) {
        case (false, false): return "\(trimmedName) (\(trimmedEmail))"
        case (false, true): return trimmedName
        case (true, false): return trimmedEmail
        case (true, true): return "Zunder-Besitzer"
        }
    }
}

/// Beliebiger JSON-Wert für das `value`-Feld einer Operation.
/// Bewusst schmal gehalten: Funke schreibt nur Strings und kleine Objekte.
enum JSONValue: Codable, Equatable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Kein gültiger JSON-Wert."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// Eine Feld-Operation im Zunder-Wire-Format (Vertrag Abschnitt 2.3):
/// `{"op_id","entity","entity_id","field","value","hlc"}`.
///
/// Wird beim Erfassen einmal erzeugt und – falls gepuffert – unverändert
/// persistiert, damit ein Nachsenden byte-identisch ist (Idempotenz über `op_id`).
struct ZunderOp: Codable, Equatable, Sendable, Hashable {
    let opID: String
    let entity: String
    let entityID: String
    let field: String
    let value: JSONValue
    let hlc: String

    private enum CodingKeys: String, CodingKey {
        case opID = "op_id"
        case entity
        case entityID = "entity_id"
        case field
        case value
        case hlc
    }

    init(opID: String, entity: String, entityID: String, field: String, value: JSONValue, hlc: String) {
        self.opID = opID
        self.entity = entity
        self.entityID = entityID
        self.field = field
        self.value = value
        self.hlc = hlc
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        opID = try container.decode(String.self, forKey: .opID)
        entity = try container.decode(String.self, forKey: .entity)
        entityID = try container.decode(String.self, forKey: .entityID)
        field = try container.decode(String.self, forKey: .field)
        // `value` muss im Wire-Format immer vorhanden sein; `null` ist erlaubt.
        value = try container.decodeIfPresent(JSONValue.self, forKey: .value) ?? .null
        hlc = try container.decode(String.self, forKey: .hlc)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(opID, forKey: .opID)
        try container.encode(entity, forKey: .entity)
        try container.encode(entityID, forKey: .entityID)
        try container.encode(field, forKey: .field)
        // Schlüssel `value` immer schreiben – auch bei `null`.
        try container.encode(value, forKey: .value)
        try container.encode(hlc, forKey: .hlc)
    }
}

/// Eine fertig vorbereitete neue Aufgabe: Aufgaben-ID plus alle Feld-Operationen.
/// Persistiert in der Offline-Queue, damit Wiederholungen exakt dieselben
/// `op_id`s/HLCs senden (keine Duplikate nach Timeout).
struct ZunderTaskDraft: Codable, Equatable, Sendable, Hashable {
    let taskID: String
    let ops: [ZunderOp]
}

/// Ein Fälligkeitsdatum aus Zunder: entweder reiner Kalendertag
/// (`YYYY-MM-DD`) oder ein Zeitpunkt (RFC 3339 mit Offset).
enum ZunderDue: Equatable, Sendable, Hashable {
    /// Reiner Tag, als lokaler Tagesbeginn abgebildet.
    case day(Date)
    /// Konkreter Zeitpunkt.
    case dateTime(Date)

    var date: Date {
        switch self {
        case .day(let date), .dateTime(let date): return date
        }
    }

    var hasTime: Bool {
        if case .dateTime = self { return true }
        return false
    }

    /// Parst `YYYY-MM-DD` (im übergebenen Kalender) oder RFC 3339
    /// (mit/ohne Sekundenbruchteile). `nil` bei unbekanntem Format.
    static func parse(_ raw: String, calendar: Calendar) -> ZunderDue? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let day = parseDay(text, calendar: calendar) {
            return .day(day)
        }
        if let instant = ZunderTimestamp.parse(text) {
            return .dateTime(instant)
        }
        return nil
    }

    private static func parseDay(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard text.count == 10, parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        // Ungültige Tage (z. B. 2026-02-30) nicht stillschweigend verschieben.
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }
}

/// RFC-3339-Zeitstempel lesen (Zunder liefert teils Millisekunden).
enum ZunderTimestamp {
    static func parse(_ text: String) -> Date? {
        // ISO8601DateFormatter ist nicht Sendable → pro Aufruf frisch erzeugen.
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
