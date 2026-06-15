import Foundation

/// Geteilte Schlüssel + Payload-Bau für das WatchConnectivity-Relay (Watch → iPhone).
/// Plattformneutral/testbar. Nutzt nur Property-List-Typen — Anforderung von
/// `transferUserInfo`. Wird von Watch-Sender und iPhone-Empfänger geteilt.
///
/// `nonisolated`, damit es auch in Targets mit „default actor isolation = MainActor"
/// (Xcode 26+) aus den nonisolated WCSessionDelegate-Methoden nutzbar bleibt.
nonisolated enum WatchCapture {
    static let textKey = "funke.capture.text"
    static let idKey = "funke.capture.id"
    static let createdAtKey = "funke.capture.createdAt"
    static let ackIDKey = "funke.ack.id"
    static let ackOutcomeKey = "funke.ack.outcome"

    /// Sende-Payload (Watch → iPhone).
    static func payload(text: String, id: UUID, createdAt: Date) -> [String: Any] {
        [
            textKey: text,
            idKey: id.uuidString,
            createdAtKey: ISO8601DateFormatter().string(from: createdAt),
        ]
    }

    /// Liest eine empfangene Capture-Payload (iPhone-Seite). `nil` bei ungültig/leer.
    static func parse(_ userInfo: [String: Any]) -> (text: String, id: String)? {
        guard let text = userInfo[textKey] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let id = userInfo[idKey] as? String, !id.isEmpty else {
            return nil
        }
        return (text, id)
    }

    /// Quittungs-Payload (iPhone → Watch).
    static func ack(id: String, outcome: String) -> [String: Any] {
        [ackIDKey: id, ackOutcomeKey: outcome]
    }
}
