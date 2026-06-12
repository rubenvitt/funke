import Foundation
import Security

/// Sicherer Geheimnis-Speicher auf Basis des Keychain (`kSecClassGenericPassword`).
/// Werte werden als UTF-8-Daten unter `account = SecretKey.rawValue` abgelegt.
/// Secrets werden niemals geloggt.
final class KeychainStore: SecretStoring {
    private let service: String

    init(service: String = "email.rubeen.funke") {
        self.service = service
    }

    // MARK: - SecretStoring

    func string(for key: SecretKey) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            // Nicht gefunden ist ein erwarteter Zustand (nil), kein Fehler.
            return nil
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setString(_ value: String?, for key: SecretKey) throws {
        guard let value else {
            try delete(key)
            return
        }
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query = baseQuery(for: key)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(Int32(addStatus))
            }
        default:
            throw KeychainError.unexpectedStatus(Int32(updateStatus))
        }
    }

    // MARK: - Private

    private func delete(_ key: SecretKey) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(Int32(status))
        }
    }

    private func baseQuery(for key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}
