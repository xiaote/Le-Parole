import Foundation
import Security

/// Minimal Keychain wrapper for secrets that must not live in the SQLite
/// database, which is copied verbatim into every exported backup.
enum KeychainStore {
    nonisolated static let geminiApiKey = "geminiApiKey"

    nonisolated private static let service = Bundle.main.bundleIdentifier ?? "Le Parole"

    nonisolated private static func query(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    nonisolated static func get(_ key: String) -> String? {
        var query = query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores `value`, or deletes the item when `value` is empty.
    @discardableResult
    nonisolated static func set(_ value: String, for key: String) -> Bool {
        guard !value.isEmpty else { return delete(key) }

        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query(for: key) as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }

        let newItem = query(for: key).merging(attributes) { $1 }
        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    nonisolated static func delete(_ key: String) -> Bool {
        let status = SecItemDelete(query(for: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
