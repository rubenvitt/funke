import Foundation
#if os(iOS) && canImport(WatchConnectivity)
import WatchConnectivity
import UIKit

/// iPhone-Empfänger des Watch-Relays. Eingehende Captures (`transferUserInfo`)
/// werden über den geteilten `CaptureRouter` klassifiziert + geroutet.
///
/// Hintergrund-Wake gibt nur wenige Sekunden — daher Background-Task-Schutz, und
/// bei Fehler puffert der Router den Rohtext (kein stiller Verlust). Verarbeitung
/// passiert opportunistisch; die OfflineQueue deckt das knappe Zeitbudget ab.
final class PhoneRelay: NSObject, WCSessionDelegate {
    static let shared = PhoneRelay()

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    // Pflicht auf iOS (Multi-Watch): nach Deaktivierung reaktivieren.
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let capture = WatchCapture.parse(userInfo) else { return }

        let token = UIApplication.shared.beginBackgroundTask(withName: "FunkeWatchRelay")
        Task { @MainActor in
            defer { UIApplication.shared.endBackgroundTask(token) }
            let services = CaptureServices.make()
            let config = services.settings.routerConfig
            do {
                let outcome = try await services.router.route(rawText: capture.text, config: config)
                let label: String
                switch outcome {
                case .task(let queued): label = queued ? "task-queued" : "task"
                case .note(let queued): label = queued ? "note-queued" : "note"
                }
                session.transferUserInfo(WatchCapture.ack(id: capture.id, outcome: label))
            } catch {
                // Nicht-Transport-Fehler (z. B. fehlende Inbox-Liste): Rohtext puffern,
                // damit nichts verloren geht; beim nächsten App-Start nachgesendet.
                await services.router.bufferNote(rawText: capture.text, config: config)
                session.transferUserInfo(WatchCapture.ack(id: capture.id, outcome: "note-queued"))
            }
        }
    }
}
#endif
