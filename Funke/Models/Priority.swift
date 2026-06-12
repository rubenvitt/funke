import Foundation

/// Aufgaben-Priorität. Rohwerte entsprechen exakt dem ClickUp-Mapping
/// (1 = urgent, 2 = high, 3 = normal, 4 = low).
enum Priority: Int, CaseIterable, Codable, Sendable, Hashable {
    case urgent = 1
    case high = 2
    case normal = 3
    case low = 4

    /// Wert, den die ClickUp-API erwartet.
    var clickUpValue: Int { rawValue }

    init?(clickUpValue: Int) {
        self.init(rawValue: clickUpValue)
    }

    /// Schema-stabiles englisches Label für KI-Provider (JSON).
    var aiLabel: String {
        switch self {
        case .urgent: return "urgent"
        case .high: return "high"
        case .normal: return "normal"
        case .low: return "low"
        }
    }

    /// Robuste Rückkonvertierung aus KI-Antworten (englisch oder deutsch).
    init?(aiLabel rawLabel: String) {
        switch rawLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "urgent", "dringend": self = .urgent
        case "high", "hoch": self = .high
        case "normal", "mittel", "medium": self = .normal
        case "low", "niedrig": self = .low
        default: return nil
        }
    }

    /// Deutscher Anzeigename für die UI.
    var displayName: String {
        switch self {
        case .urgent: return "Dringend"
        case .high: return "Hoch"
        case .normal: return "Normal"
        case .low: return "Niedrig"
        }
    }

    /// SF-Symbol für die Listendarstellung.
    var symbolName: String {
        switch self {
        case .urgent: return "exclamationmark.2"
        case .high: return "exclamationmark"
        case .normal: return "equal"
        case .low: return "arrow.down"
        }
    }
}
