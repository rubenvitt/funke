import Foundation

/// Eine lokal gepufferte Aufgabe, die bei fehlender Verbindung gespeichert
/// und beim nächsten Start/Refresh nachgesendet wird. Niemals stiller Verlust.
///
/// Trägt den beim Erfassen erzeugten `ZunderTaskDraft` (Aufgaben-ID, `op_id`s,
/// HLCs). Beim Nachsenden gehen exakt diese Operationen raus – Zunder nimmt
/// bekannte `op_id`s ohne Wirkung erneut an, ein Timeout erzeugt also keine Duplikate.
///
/// Dekodierung ist tolerant: Einträge aus der ClickUp-Zeit (`name`,
/// `markdownDescription`, `priority`) werden gelesen; sie haben noch keinen
/// Entwurf (`draft == nil`) und bekommen beim Nachsenden einen frischen, der vor
/// dem Senden persistiert wird. Die alte Priorität wird verworfen (Zunder kennt keine).
struct PendingCapture: Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let description: String?
    let createdAt: Date
    /// Persistierter Zunder-Entwurf; `nil` nur bei migrierten Alt-Einträgen.
    let draft: ZunderTaskDraft?

    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        createdAt: Date = Date(),
        draft: ZunderTaskDraft?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.createdAt = createdAt
        self.draft = draft
    }

    /// Kopie mit (neuem) Entwurf – gleiche Queue-ID, damit sie den Eintrag ersetzt.
    func withDraft(_ draft: ZunderTaskDraft) -> PendingCapture {
        PendingCapture(id: id, title: title, description: description, createdAt: createdAt, draft: draft)
    }
}

extension PendingCapture: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, description, createdAt, draft
        // Alt-Schlüssel aus der ClickUp-Zeit (nur lesen).
        case name, markdownDescription
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        if let title = try container.decodeIfPresent(String.self, forKey: .title) {
            self.title = title
        } else {
            self.title = try container.decode(String.self, forKey: .name)
        }
        description = try container.decodeIfPresent(String.self, forKey: .description)
            ?? container.decodeIfPresent(String.self, forKey: .markdownDescription)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        draft = try container.decodeIfPresent(ZunderTaskDraft.self, forKey: .draft)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(draft, forKey: .draft)
    }
}
