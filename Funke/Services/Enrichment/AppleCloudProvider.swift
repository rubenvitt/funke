import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// KI-Provider auf Basis von Apple Private Cloud Compute (iOS 27+).
///
/// Nutzt dieselben `@Generable`-Typen wie der On-Device-Provider (definiert in
/// `AppleOnDeviceProvider.swift`). Erfordert das managed Entitlement
/// `com.apple.developer.private-cloud-compute`; ohne dieses meldet
/// `availability` sauber „nicht verfügbar".
@available(iOS 27.0, macOS 27.0, *)
struct AppleCloudProvider: AIEnrichmentProvider {
    let kind: EnrichmentProviderKind = .appleCloud

    func availability() async -> ProviderAvailability {
        let model = PrivateCloudComputeLanguageModel()
        switch model.availability {
        case .available:
            // `supportsLocale` ist auf PrivateCloudComputeLanguageModel nicht
            // dokumentiert/verifiziert (nur auf SystemLanguageModel). Das
            // Cloud-Modell ist mehrsprachig – Verfügbarkeit allein über `.availability`.
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("Gerät unterstützt Private Cloud Compute nicht.")
        case .unavailable(.systemNotReady):
            return .unavailable("Private Cloud Compute ist noch nicht bereit.")
        case .unavailable(let other):
            return .unavailable("Cloud-Modell nicht verfügbar: \(other).")
        }
    }

    func enrich(_ rawText: String) async throws -> EnrichmentSuggestion {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EnrichmentError.emptyInput }

        let model = PrivateCloudComputeLanguageModel()
        let session = LanguageModelSession(model: model, instructions: EnrichmentPrompt.systemInstruction)
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

        let model = PrivateCloudComputeLanguageModel()
        let session = LanguageModelSession(model: model, instructions: NotePrompt.systemInstruction)
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

        let model = PrivateCloudComputeLanguageModel()
        let session = LanguageModelSession(model: model, instructions: ClassifyPrompt.systemInstruction)
        do {
            let response = try await session.respond(to: rawText, generating: ClassifyDraft.self)
            return response.content.toClassification()
        } catch {
            throw AppleModelSupport.map(error)
        }
    }
}

#else

/// Stub, falls FoundationModels nicht verfügbar ist. Meldet sich immer als
/// nicht verfügbar, damit der Composition-Root überall kompiliert.
struct AppleCloudProvider: AIEnrichmentProvider {
    let kind: EnrichmentProviderKind = .appleCloud

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
