import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Geteilte @Generable-Typen
//
// Diese Typen werden sowohl vom On-Device- als auch vom Cloud-Provider genutzt.
// Nicht-optionale `String`-Felder mit „leer = nichts", weil optionale Felder
// unter `@Generable` doku-seitig unbestätigt sind.

@available(iOS 26.0, macOS 26.0, *)
@Generable
enum DraftPriority {
    case urgent, high, normal, low

    /// Totale Abbildung ohne Raw-Value – überlebt, falls `@Generable` keine
    /// Raw-Value-Enums akzeptiert (im CLT-Makro-Probe nicht verifizierbar).
    var asPriority: Priority {
        switch self {
        case .urgent: return .urgent
        case .high: return .high
        case .normal: return .normal
        case .low: return .low
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct EnrichmentDraft {
    @Guide(description: "Knapper Aufgaben-Titel")
    var title: String
    @Guide(description: "Beschreibung; leerer String wenn keine")
    var details: String
    @Guide(description: "Priorität")
    var priority: DraftPriority
}

/// Geteilter Notiz-Entwurf für beide Apple-Provider (On-Device + Cloud).
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct NoteDraftGen {
    @Guide(description: "Knapper Titel")
    var title: String
    @Guide(description: "Aufgeräumter Markdown-Body")
    var body: String
}

@available(iOS 26.0, macOS 26.0, *)
extension NoteDraftGen {
    /// Wandelt den generierten Entwurf in eine Notiz um (leerer Body → Titel).
    func toSuggestion() -> NoteSuggestion {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return NoteSuggestion(
            title: trimmedTitle,
            body: trimmedBody.isEmpty ? trimmedTitle : trimmedBody
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension EnrichmentDraft {
    /// Wandelt den generierten Entwurf in einen Vorschlag um (leere Strings → nil).
    func toSuggestion() -> EnrichmentSuggestion {
        EnrichmentSuggestion(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: AppleModelSupport.nonEmpty(details),
            priority: priority.asPriority
        )
    }
}

/// Geteiltes Klassifikations-Ergebnis (Task vs. Notiz) für beide Apple-Provider.
@available(iOS 26.0, macOS 26.0, *)
@Generable
enum CaptureKindGen {
    case task, note

    var asKind: CaptureKind {
        switch self {
        case .task: return .task
        case .note: return .note
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct ClassifyDraft {
    @Guide(description: "task = umsetzbare Aufgabe/To-do (oft mit Verb); note = reine Information/Gedanke ohne Handlung")
    var kind: CaptureKindGen
    @Guide(description: "Knapper Titel")
    var title: String
    @Guide(description: "Aufgeräumter Body; bei Notizen der ausgearbeitete Inhalt")
    var body: String
    @Guide(description: "Priorität (nur für Aufgaben relevant; bei Notizen normal)")
    var priority: DraftPriority
}

@available(iOS 26.0, macOS 26.0, *)
extension ClassifyDraft {
    /// Wandelt den generierten Entwurf in eine Klassifikation um (leerer Body → Titel).
    func toClassification() -> CaptureClassification {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return CaptureClassification(
            kind: kind.asKind,
            title: trimmedTitle,
            body: trimmedBody.isEmpty ? trimmedTitle : trimmedBody,
            priority: priority.asPriority
        )
    }
}

// MARK: - Gemeinsame Helfer für beide Apple-Provider

@available(iOS 26.0, macOS 26.0, *)
enum AppleModelSupport {
    static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Mappt Fehler aus der Guided Generation auf typisierte `EnrichmentError`.
    static func map(_ error: Error) -> EnrichmentError {
        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .unsupportedLanguageOrLocale:
                return .unsupportedLanguage
            default:
                return .invalidResponse(generationError.localizedDescription)
            }
        }
        return .invalidResponse(error.localizedDescription)
    }
}

/// KI-Provider auf Basis des geräteinternen Apple-Sprachmodells (iOS 26+).
@available(iOS 26.0, macOS 26.0, *)
struct AppleOnDeviceProvider: AIEnrichmentProvider {
    let kind: EnrichmentProviderKind = .appleOnDevice

    func availability() async -> ProviderAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            if model.supportsLocale(Locale(identifier: "de")) == false {
                return .unavailable("Deutsch wird vom Gerätemodell nicht unterstützt.")
            }
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("Gerät unterstützt Apple Intelligence nicht.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence ist nicht aktiviert.")
        case .unavailable(.modelNotReady):
            return .unavailable("Das Modell ist noch nicht bereit (Download/Vorbereitung).")
        case .unavailable(let other):
            return .unavailable("Gerätemodell nicht verfügbar: \(other).")
        }
    }

    func enrich(_ rawText: String) async throws -> EnrichmentSuggestion {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EnrichmentError.emptyInput }

        let session = LanguageModelSession(instructions: EnrichmentPrompt.systemInstruction)
        do {
            let response = try await session.respond(to: rawText, generating: EnrichmentDraft.self)
            return response.content.toSuggestion()
        } catch {
            throw AppleModelSupport.map(error)
        }
    }

    func enrichNote(_ rawText: String) async throws -> NoteSuggestion {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EnrichmentError.emptyInput }

        let session = LanguageModelSession(instructions: NotePrompt.systemInstruction)
        do {
            let response = try await session.respond(to: rawText, generating: NoteDraftGen.self)
            return response.content.toSuggestion()
        } catch {
            throw AppleModelSupport.map(error)
        }
    }

    func classify(_ rawText: String) async throws -> CaptureClassification {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EnrichmentError.emptyInput }

        let session = LanguageModelSession(instructions: ClassifyPrompt.systemInstruction)
        do {
            let response = try await session.respond(to: rawText, generating: ClassifyDraft.self)
            return response.content.toClassification()
        } catch {
            throw AppleModelSupport.map(error)
        }
    }
}

#else

/// Stub, falls FoundationModels nicht verfügbar ist (z. B. macOS-Typecheck in
/// den Command Line Tools). Meldet sich immer als nicht verfügbar.
struct AppleOnDeviceProvider: AIEnrichmentProvider {
    let kind: EnrichmentProviderKind = .appleOnDevice

    func availability() async -> ProviderAvailability {
        .unavailable("FoundationModels nicht verfügbar")
    }

    func enrich(_ rawText: String) async throws -> EnrichmentSuggestion {
        throw EnrichmentError.providerUnavailable("FoundationModels nicht verfügbar")
    }

    func enrichNote(_ rawText: String) async throws -> NoteSuggestion {
        throw EnrichmentError.providerUnavailable("FoundationModels nicht verfügbar")
    }

    func classify(_ rawText: String) async throws -> CaptureClassification {
        throw EnrichmentError.providerUnavailable("FoundationModels nicht verfügbar")
    }
}

#endif
