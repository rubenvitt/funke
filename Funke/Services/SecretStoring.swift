import Foundation

/// Identifiziert ein im Keychain abgelegtes Geheimnis.
enum SecretKey: String, CaseIterable, Sendable {
    case clickUpToken = "clickup_token"
    case anthropicKey = "anthropic_key"
    case openRouterKey = "openrouter_key"
}

/// Abstraktion über den sicheren Geheimnis-Speicher (Keychain).
/// Lesen liefert `nil`, wenn nichts hinterlegt ist; Schreiben kann fehlschlagen
/// und meldet das sichtbar (kein stiller Fehler).
protocol SecretStoring: Sendable {
    func string(for key: SecretKey) -> String?
    func setString(_ value: String?, for key: SecretKey) throws
    func hasValue(for key: SecretKey) -> Bool
}

extension SecretStoring {
    func hasValue(for key: SecretKey) -> Bool {
        guard let value = string(for: key) else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
