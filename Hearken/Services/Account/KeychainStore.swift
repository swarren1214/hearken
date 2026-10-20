import Foundation
import OSLog
import Security

/// Minimal Keychain wrapper for small strings such as the Apple user ID.
///
/// Nonisolated so it can run off the main thread: each call is a synchronous round trip to
/// securityd, which can block for a noticeable time at launch. Prefer `readOffMain(_:)` from
/// async code on the main actor.
nonisolated enum KeychainStore {
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
            Logger(subsystem: "com.stephenwarren.hearken", category: "keychain").error("save failed with OSStatus \(result)")
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

    /// `read(_:)` on a background thread, so the main thread isn't held up waiting on securityd.
    static func readOffMain(_ key: String) async -> String? {
        await Task.detached(priority: .userInitiated) { read(key) }.value
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
