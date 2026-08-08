import Foundation
import Security

/// The bridge bearer token, kept in the Keychain.
///
/// Deliberately not `UserDefaults`: that is a plist inside the app container,
/// readable from an unencrypted device backup and from any file-level inspection
/// of the container. The Keychain item below is also excluded from backups
/// (`ThisDeviceOnly`), so the token cannot travel to another device.
enum KeychainStore {
    /// Distinct from the bundle identifier so that renaming the app later does
    /// not silently orphan an existing token.
    private static let service = "com.grizzly.hermes-voice.bridge"
    private static let account = "bearerToken"

    /// Write (or overwrite) the token. An empty string clears it.
    static func saveToken(_ token: String) {
        guard !token.isEmpty else {
            deleteToken()
            return
        }
        guard let data = token.data(using: .utf8) else { return }

        // SecItemUpdate only works on an item that exists, and SecItemAdd fails
        // with errSecDuplicateItem on one that does. Delete-then-add is the one
        // sequence that behaves the same whether or not a token is already set.
        deleteToken()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // AfterFirstUnlock, not WhenUnlocked: a turn started from the lock
            // screen or continued in the background must still be able to read
            // the token. ThisDeviceOnly keeps it out of backups.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else {
            return nil
        }
        return token
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
