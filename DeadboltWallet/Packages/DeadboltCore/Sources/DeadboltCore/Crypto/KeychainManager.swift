import Foundation
import Security

public enum KeychainManager {
    private static let service = "com.deadbolt.wallet"

    /// Store a 32-byte seed in Keychain, keyed by Base58 address
    public static func storeSeed(_ seed: Data, address: String) throws {
        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: address,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: address,
            kSecValueData as String: seed,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SolanaError.keychainError(status)
        }
    }

    /// Retrieve a seed from Keychain by Base58 address
    public static func retrieveSeed(address: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: address,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                throw SolanaError.keychainItemNotFound
            }
            throw SolanaError.keychainError(status)
        }

        return data
    }

    /// List all stored wallet addresses
    public static func listStoredAddresses() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw SolanaError.keychainError(status)
        }

        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    /// Delete a seed from Keychain by address
    public static func deleteSeed(address: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: address,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SolanaError.keychainError(status)
        }
    }
}
