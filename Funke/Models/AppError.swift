import Foundation

/// Fehler aus der ClickUp-Kommunikation. Bewusst `Equatable` (keine rohen
/// `Error`-Werte gespeichert), damit ViewModels testbar bleiben.
enum ClickUpError: LocalizedError, Equatable {
    case missingToken
    case notConfigured(String)
    case invalidURL
    case transport(String)
    case http(status: Int, message: String?)
    case decoding(String)
    case noDoneStatus(listName: String?)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Kein ClickUp-Token hinterlegt. Bitte in den Einstellungen eintragen."
        case .notConfigured(let what):
            return "ClickUp ist nicht vollständig eingerichtet: \(what)."
        case .invalidURL:
            return "Interner Fehler: ungültige ClickUp-URL."
        case .transport(let message):
            return "Netzwerkfehler: \(message)"
        case .http(let status, let message):
            if let message, !message.isEmpty {
                return "ClickUp-Fehler (\(status)): \(message)"
            }
            return "ClickUp-Fehler (HTTP \(status))."
        case .decoding(let message):
            return "Antwort von ClickUp nicht lesbar: \(message)"
        case .noDoneStatus(let listName):
            let suffix = listName.map { " in Liste „\($0)“" } ?? ""
            return "Kein abgeschlossener Status\(suffix) gefunden."
        }
    }
}

/// Fehler aus der KI-Veredelung. Nie blockierend – der rohe Text bleibt anlegbar.
enum EnrichmentError: LocalizedError, Equatable {
    case emptyInput
    case providerUnavailable(String)
    case missingAPIKey(provider: String)
    case transport(String)
    case http(status: Int, message: String?)
    case invalidResponse(String)
    case unsupportedLanguage

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Kein Text zum Veredeln vorhanden."
        case .providerUnavailable(let reason):
            return "KI-Provider nicht verfügbar: \(reason)"
        case .missingAPIKey(let provider):
            return "Kein API-Schlüssel für \(provider) hinterlegt."
        case .transport(let message):
            return "Netzwerkfehler bei der KI-Anfrage: \(message)"
        case .http(let status, let message):
            if let message, !message.isEmpty {
                return "KI-Fehler (\(status)): \(message)"
            }
            return "KI-Fehler (HTTP \(status))."
        case .invalidResponse(let detail):
            return "KI-Antwort nicht verwertbar: \(detail)"
        case .unsupportedLanguage:
            return "Das gewählte KI-Modell unterstützt die Eingabesprache nicht."
        }
    }
}

/// Fehler aus der Sprachtranskription.
enum SpeechError: LocalizedError, Equatable {
    case notAuthorized
    case recognizerUnavailable
    case audioSession(String)
    case noInput

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Mikrofon- oder Spracherkennungs-Berechtigung fehlt. Bitte in den iOS-Einstellungen erlauben."
        case .recognizerUnavailable:
            return "Spracherkennung für Deutsch ist auf diesem Gerät nicht verfügbar."
        case .audioSession(let message):
            return "Audio konnte nicht gestartet werden: \(message)"
        case .noInput:
            return "Keine Sprache erkannt."
        }
    }
}

/// Fehler beim Schreiben einer Notiz über einen `NoteSink` (Server-Relay oder
/// lokales Dateisystem). `transport` signalisiert „später erneut" (Offline-Queue).
enum NoteSinkError: LocalizedError, Equatable {
    case notConfigured(String)
    case transport(String)
    case http(status: Int, message: String?)
    case fileSystem(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let what):
            return "Notiz-Ziel nicht eingerichtet: \(what)."
        case .transport(let message):
            return "Netzwerkfehler beim Senden der Notiz: \(message)"
        case .http(let status, let message):
            if let message, !message.isEmpty {
                return "Relay-Fehler (\(status)): \(message)"
            }
            return "Relay-Fehler (HTTP \(status))."
        case .fileSystem(let message):
            return "Notiz konnte nicht gespeichert werden: \(message)"
        case .invalidResponse(let detail):
            return "Unerwartete Antwort vom Relay-Server: \(detail)"
        }
    }
}

/// Fehler aus dem Keychain-Zugriff.
enum KeychainError: LocalizedError, Equatable {
    case unexpectedStatus(Int32)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain-Fehler (Status \(status))."
        case .encodingFailed:
            return "Wert konnte nicht für den Keychain kodiert werden."
        }
    }
}
