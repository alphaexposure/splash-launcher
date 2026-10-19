import Foundation
import Security

protocol SplashAPIKeyStoring {
    func read() throws -> String?
    func save(_ key: String) throws
    func remove() throws
}

enum SplashAPIKeyStoreError: LocalizedError {
    case keychain(OSStatus)
    case invalidKey

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
        case .invalidKey:
            return "API key must contain only visible ASCII characters without spaces."
        }
    }
}

/// Keeps the key in the user's Keychain. The process receives it only as an environment value.
final class SplashAPIKeyStore: SplashAPIKeyStoring {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "SplashLauncher.SplashAPIKey",
         kSecAttrAccount as String: "default"]
    }

    func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SplashAPIKeyStoreError.keychain(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw SplashAPIKeyStoreError.invalidKey
        }
        return key
    }

    func save(_ key: String) throws {
        guard !key.isEmpty, key.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw SplashAPIKeyStoreError.invalidKey
        }
        let data = Data(key.utf8)
        var request = query
        request[kSecValueData as String] = data
        let status = SecItemAdd(request as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else { throw SplashAPIKeyStoreError.keychain(updateStatus) }
        } else if status != errSecSuccess {
            throw SplashAPIKeyStoreError.keychain(status)
        }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SplashAPIKeyStoreError.keychain(status)
        }
    }
}
