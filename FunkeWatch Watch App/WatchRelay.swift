import Foundation
#if os(watchOS) && canImport(WatchConnectivity)
import WatchConnectivity

/// Watch-Sender: erfasste Texte gehen per `transferUserInfo` ans iPhone
/// (garantierte, verlustfreie Zustellung, auch ohne aktives iPhone). Klassifikation
/// + Vault/ClickUp-Routing macht das iPhone — die Watch hält keine Secrets.
@MainActor
final class WatchRelay: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchRelay()

    /// Letzter sichtbarer Status (übergeben / Quittung vom iPhone).
    @Published var lastStatus: String?

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Fire-and-forget; queued auch ohne Reachability.
    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        WCSession.default.transferUserInfo(
            WatchCapture.payload(text: trimmed, id: UUID(), createdAt: Date())
        )
        lastStatus = "An iPhone übergeben"
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    /// Quittung vom iPhone (kommt ggf. erst beim nächsten Aktivwerden der Watch).
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let outcome = userInfo[WatchCapture.ackOutcomeKey] as? String
        Task { @MainActor in
            if let outcome { self.lastStatus = Self.ackText(outcome) }
        }
    }

    private static func ackText(_ outcome: String) -> String {
        switch outcome {
        case "task": return "Aufgabe angelegt"
        case "note": return "Notiz gespeichert"
        case "task-queued", "note-queued": return "Gepuffert (offline)"
        default: return "Verarbeitet"
        }
    }
}
#endif
