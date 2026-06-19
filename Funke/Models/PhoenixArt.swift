import Foundation

/// Die „Art" einer Aufgabe in Rubens Phönix-Progression — gespeichert als
/// ClickUp-Dropdown-Custom-Field „🗓️ Art" auf der Phönix-Liste.
///
/// Reihenfolge entspricht der Eskalation: Ära → Zyklus → Feuersturm → Aschezeit
/// → Feuer → Flamme → Funke. Die kleinen, planbaren Einheiten (Feuer/Flamme/Funke)
/// sind die Fokus-Blöcke der Tages-Timeline.
enum PhoenixArt: String, CaseIterable, Sendable, Hashable, Codable {
    case aera        // Phönix-Ära
    case zyklus      // Phönix-Zyklus
    case feuersturm  // Feuersturm (12-Wochen-Sprint)
    case aschezeit   // Aschezeit (Regeneration)
    case feuer       // Feuer (großer Block)
    case flamme      // Flamme (~2 h Fokus)
    case funke       // Funke (~30 min)

    /// Auflösung aus dem ClickUp-Dropdown-Optionsnamen (z. B. „Phönix-Ära", „Flamme").
    /// Toleriert Varianten ohne Diakritika und unterschiedliche Bindestriche.
    init?(clickUpName raw: String) {
        let normalized = raw
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "phonix ara", "phonix aera", "ara", "aera": self = .aera
        case "phonix zyklus", "zyklus": self = .zyklus
        case "feuersturm": self = .feuersturm
        case "aschezeit": self = .aschezeit
        case "feuer": self = .feuer
        case "flamme": self = .flamme
        case "funke": self = .funke
        default: return nil
        }
    }

    /// Anzeigename im UI.
    var displayName: String {
        switch self {
        case .aera: return "Phönix-Ära"
        case .zyklus: return "Phönix-Zyklus"
        case .feuersturm: return "Feuersturm"
        case .aschezeit: return "Aschezeit"
        case .feuer: return "Feuer"
        case .flamme: return "Flamme"
        case .funke: return "Funke"
        }
    }

    /// Standard-Dauer in Minuten, falls die Aufgabe kein `time_estimate` hat.
    var defaultDurationMinutes: Int {
        switch self {
        case .funke: return 30
        case .flamme: return 120
        case .feuer: return 240
        default: return 60
        }
    }

    /// Kurzlabel für Timeline-Karten (z. B. „Flamme · 2 h").
    var focusLabel: String {
        switch self {
        case .funke: return "Funke · 30 min"
        case .flamme: return "Flamme · 2 h"
        case .feuer: return "Feuer · 4 h"
        default: return displayName
        }
    }

    /// Ist es ein planbarer Fokus-Block auf der Timeline?
    var isFocusBlock: Bool {
        self == .funke || self == .flamme || self == .feuer
    }
}

// MARK: - Phönix-Überblick (Feuersturm + Ziele)

/// Aktueller Feuersturm-Sprint: Woche X von N.
struct FeuersturmInfo: Sendable, Equatable {
    let weekIndex: Int   // 1-basiert
    let totalWeeks: Int
    let title: String

    /// Berechnet Woche X von N aus Start-/Enddatum eines Feuersturm-Tasks.
    /// Robust gegen vertauschte/fehlende Daten; klemmt in [1, N].
    static func from(start: Date?, due: Date?, now: Date, title: String) -> FeuersturmInfo? {
        guard let start, let due, due > start else { return nil }
        let secondsPerWeek: TimeInterval = 7 * 24 * 60 * 60
        let total = max(1, Int((due.timeIntervalSince(start) / secondsPerWeek).rounded()))
        let elapsed = now.timeIntervalSince(start)
        let week = Int((elapsed / secondsPerWeek).rounded(.down)) + 1
        let clamped = min(max(week, 1), total)
        return FeuersturmInfo(weekIndex: clamped, totalWeeks: total, title: title)
    }
}

/// Ein Ziel der Phönix-Progression (Task „Ziel 1/2/3 …").
struct PhoenixGoal: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let statusName: String
    /// 0…1, falls aus ClickUp ableitbar (Fortschritts-Feld) — sonst `nil`.
    let progress: Double?
}

/// Read-only-Überblick über die Phönix-Liste für „Heute"-Chip und Einstellungen.
struct PhoenixOverview: Sendable, Equatable {
    let feuersturm: FeuersturmInfo?
    let goals: [PhoenixGoal]
}
