import Foundation

/// Fasst alle KI-Provider zusammen und wählt anhand der Einstellungen.
///
/// Provider werden on-demand gebaut. Die KI ist additiv und nie blockierend –
/// Fehler werden geworfen, nie verschluckt. Apple-Provider sind OS-gegated:
/// auf zu alten Systemen melden sie „nicht verfügbar" bzw. werfen
/// `providerUnavailable`.
struct EnrichmentService: EnrichmentServicing {
    private let secrets: SecretStoring
    private let session: URLSession

    /// Platzhalter-Modell nur für die OpenRouter-Verfügbarkeitsprüfung
    /// (die nur am hinterlegten Schlüssel hängt, nicht am Modell).
    private static let availabilityProbeModel = "openai/gpt-5-nano"

    init(secrets: SecretStoring, session: URLSession = .shared) {
        self.secrets = secrets
        self.session = session
    }

    // MARK: - Verfügbarkeit

    func availability(for kind: EnrichmentProviderKind) async -> ProviderAvailability {
        switch kind {
        case .anthropic:
            return await anthropicProvider().availability()
        case .openRouter:
            // Für die reine Verfügbarkeitsprüfung genügt irgendein Modellname;
            // die Availability hängt nur am Schlüssel, nicht am Modell.
            return await openRouterProvider(model: Self.availabilityProbeModel).availability()
        case .appleOnDevice:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                return await AppleOnDeviceProvider().availability()
            } else {
                return .unavailable("Apple On-Device benötigt iOS 26 oder neuer.")
            }
            #else
            return await AppleOnDeviceProvider().availability()
            #endif
        case .appleCloud:
            #if canImport(FoundationModels)
            if #available(iOS 27.0, macOS 27.0, *) {
                return await AppleCloudProvider().availability()
            } else {
                return .unavailable("Apple Cloud benötigt iOS 27 oder neuer.")
            }
            #else
            return await AppleCloudProvider().availability()
            #endif
        }
    }

    // MARK: - Veredelung

    func enrich(
        _ rawText: String,
        using kind: EnrichmentProviderKind,
        openRouterModel: String
    ) async throws -> EnrichmentSuggestion {
        switch kind {
        case .anthropic:
            return try await anthropicProvider().enrich(rawText)
        case .openRouter:
            return try await openRouterProvider(model: openRouterModel).enrich(rawText)
        case .appleOnDevice:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                return try await AppleOnDeviceProvider().enrich(rawText)
            } else {
                throw EnrichmentError.providerUnavailable("Apple On-Device benötigt iOS 26 oder neuer.")
            }
            #else
            return try await AppleOnDeviceProvider().enrich(rawText)
            #endif
        case .appleCloud:
            #if canImport(FoundationModels)
            if #available(iOS 27.0, macOS 27.0, *) {
                return try await AppleCloudProvider().enrich(rawText)
            } else {
                throw EnrichmentError.providerUnavailable("Apple Cloud benötigt iOS 27 oder neuer.")
            }
            #else
            return try await AppleCloudProvider().enrich(rawText)
            #endif
        }
    }

    func enrichNote(
        _ rawText: String,
        using kind: EnrichmentProviderKind,
        openRouterModel: String
    ) async throws -> NoteSuggestion {
        switch kind {
        case .anthropic:
            return try await anthropicProvider().enrichNote(rawText)
        case .openRouter:
            return try await openRouterProvider(model: openRouterModel).enrichNote(rawText)
        case .appleOnDevice:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                return try await AppleOnDeviceProvider().enrichNote(rawText)
            } else {
                throw EnrichmentError.providerUnavailable("Apple On-Device benötigt iOS 26 oder neuer.")
            }
            #else
            return try await AppleOnDeviceProvider().enrichNote(rawText)
            #endif
        case .appleCloud:
            #if canImport(FoundationModels)
            if #available(iOS 27.0, macOS 27.0, *) {
                return try await AppleCloudProvider().enrichNote(rawText)
            } else {
                throw EnrichmentError.providerUnavailable("Apple Cloud benötigt iOS 27 oder neuer.")
            }
            #else
            return try await AppleCloudProvider().enrichNote(rawText)
            #endif
        }
    }

    func classify(
        _ rawText: String,
        using kind: EnrichmentProviderKind,
        openRouterModel: String
    ) async throws -> CaptureClassification {
        switch kind {
        case .anthropic:
            return try await anthropicProvider().classify(rawText)
        case .openRouter:
            return try await openRouterProvider(model: openRouterModel).classify(rawText)
        case .appleOnDevice:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                return try await AppleOnDeviceProvider().classify(rawText)
            } else {
                throw EnrichmentError.providerUnavailable("Apple On-Device benötigt iOS 26 oder neuer.")
            }
            #else
            return try await AppleOnDeviceProvider().classify(rawText)
            #endif
        case .appleCloud:
            #if canImport(FoundationModels)
            if #available(iOS 27.0, macOS 27.0, *) {
                return try await AppleCloudProvider().classify(rawText)
            } else {
                throw EnrichmentError.providerUnavailable("Apple Cloud benötigt iOS 27 oder neuer.")
            }
            #else
            return try await AppleCloudProvider().classify(rawText)
            #endif
        }
    }

    // MARK: - Provider-Aufbau

    private func anthropicProvider() -> AnthropicProvider {
        AnthropicProvider(secrets: secrets, session: session)
    }

    private func openRouterProvider(model: String) -> OpenRouterProvider {
        OpenRouterProvider(secrets: secrets, session: session, model: model)
    }
}
