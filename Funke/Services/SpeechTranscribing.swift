import Foundation

/// Live-Sprachtranskription (Deutsch). Protokollbasiert, damit das
/// CaptureViewModel ohne echtes Audio getestet werden kann.
@MainActor
protocol SpeechTranscribing: AnyObject {
    /// True, wenn Spracherkennung grundsätzlich nutzbar ist (Gerät/Berechtigung).
    var isAvailable: Bool { get }
    /// Fordert Mikrofon- und Spracherkennungs-Berechtigung an.
    func requestAuthorization() async -> Bool
    /// Startet die Aufnahme; `onPartialResult` liefert das laufende Transkript.
    func start(onPartialResult: @escaping (String) -> Void) throws
    /// Stoppt die Aufnahme.
    func stop()
}
