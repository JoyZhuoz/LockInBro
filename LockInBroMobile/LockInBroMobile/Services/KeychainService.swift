// KeychainService.swift — LockInBro
// Secure JWT token storage in the system Keychain

import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()
    private init() {}

    private let service = "com.lockinbro.app"
    private let tokenAccount = "jwt_access"
    private let refreshAccount = "jwt_refresh"

    // MARK: - Token

    func saveToken(_ token: String) {
        save(token, account: tokenAccount)
    }

    func getToken() -> String? {
        return load(account: tokenAccount)
    }

    func saveRefreshToken(_ token: String) {
        save(token, account: refreshAccount)
    }

    func getRefreshToken() -> String? {
        return load(account: refreshAccount)
    }

    func deleteAll() {
        delete(account: tokenAccount)
        delete(account: refreshAccount)
    }

    // MARK: - Private Keychain Operations

    private func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
