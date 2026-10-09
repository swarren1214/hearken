import Foundation
import Security

/// Minimal Keychain wrapper for small strings such as the Apple user ID.
enum KeychainStore {
    private static let service = "com.stephenwarren.hearken.account"

    /// Returns false if the Keychain refused the write.
    @discardableResult
    static func save(_ value: String, for key: String) -> Bool {
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let result = SecItemAdd(attributes as CFDictionary, nil)
        if result != errSecSuccess {
            print("KeychainStore: save failed with OSStatus \(result)")
        }
        return result == errSecSuccess
    }

    static func read(_ key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
