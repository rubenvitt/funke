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
    @Guide(description: "Ein Tag; leerer String wenn keiner")
    var tag: String
}

@available(iOS 26.0, macOS 26.0, *)
extension EnrichmentDraft {
    /// Wandelt den generierten Entwurf in einen Vorschlag um (leere Strings → nil).
    func toSuggestion() -> EnrichmentSuggestion {
        EnrichmentSuggestion(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: AppleModelSupport.nonEmpty(details),
            priority: priority.asPriority,
            tag: AppleModelSupport.nonEmpty(tag)
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
}

#endif
