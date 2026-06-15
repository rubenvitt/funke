import Foundation

/// Ein Element der Offline-Queue: entweder ein ClickUp-Task oder eine Obsidian-Notiz.
/// Vereinheitlicht das Puffern beider Capture-Arten (kein stiller Verlust).
///
/// Persistiert mit stabilem, lesbarem Diskriminator (`{"kind":"task","task":{…}}`).
/// Alte reine `[PendingCapture]`-Dateien werden beim Laden migriert (siehe `OfflineQueue`).
enum PendingItem: Equatable, Sendable, Identifiable {
    case task(PendingCapture)
    case note(PendingNote)

    var id: UUID {
        switch self {
        case .task(let task): return task.id
        case .note(let note): return note.id
        }
    }
}

extension PendingItem: Codable {
    private enum CodingKeys: String, CodingKey { case kind, task, note }
    private enum Kind: String, Codable { case task, note }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .task:
            self = .task(try container.decode(PendingCapture.self, forKey: .task))
        case .note:
            self = .note(try container.decode(PendingNote.self, forKey: .note))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .task(let task):
            try container.encode(Kind.task, forKey: .kind)
            try container.encode(task, forKey: .task)
        case .note(let note):
            try container.encode(Kind.note, forKey: .kind)
            try container.encode(note, forKey: .note)
        }
    }
}
