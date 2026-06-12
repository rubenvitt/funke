import Foundation
import Speech
import AVFoundation

/// Live-Sprachtranskription (Deutsch) via `SFSpeechRecognizer` + `AVAudioEngine`.
///
/// `SFSpeechRecognizer` und `AVAudioEngine` sind plattformübergreifend verfügbar
/// (iOS/macOS), daher typecheckt diese Datei auch gegen das macOS-SDK.
/// Nur `AVAudioSession` ist iOS-spezifisch und deshalb mit `#if os(iOS)` gegatet.
@MainActor
final class SpeechTranscriber: ObservableObject, SpeechTranscribing {
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    }

    /// True, wenn ein Recognizer für Deutsch existiert und einsatzbereit ist.
    var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let speechGranted = await Self.requestSpeechAuthorization()
        guard speechGranted else { return false }
        return await Self.requestMicrophoneAuthorization()
    }

    private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func requestMicrophoneAuthorization() async -> Bool {
        #if os(iOS)
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        // macOS: Mikrofonzugriff wird vom System / Info.plist geregelt; hier
        // gibt es keinen AVAudioApplication-Prompt. Speech-Autorisierung genügt.
        return true
        #endif
    }

    // MARK: - Recording

    func start(onPartialResult: @escaping (String) -> Void) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        // Eventuell laufende Session sauber beenden, bevor neu gestartet wird.
        stop()

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechError.audioSession(error.localizedDescription)
        }
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        task = recognizer.recognitionTask(with: request) { result, _ in
            if let result {
                onPartialResult(result.bestTranscription.formattedString)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stop()
            throw SpeechError.audioSession(error.localizedDescription)
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        #if os(iOS)
        // Audio-Session freigeben, damit andere Apps weiterspielen können.
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Bewusst best-effort beim Teardown: ein Deaktivierungs-Fehler ist
            // hier nicht behebbar und darf das Beenden nicht blockieren.
        }
        #endif
    }
}
