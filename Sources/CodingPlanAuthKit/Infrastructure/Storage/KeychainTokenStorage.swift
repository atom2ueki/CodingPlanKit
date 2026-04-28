// KeychainTokenStorage.swift
// CodingPlanAuthKit

import Foundation
import Security

/// A ``TokenStorage`` implementation backed by the system Keychain.
///
/// Credentials are serialized as JSON and stored under a service name derived
/// from ``servicePrefix`` and the provider identifier (e.g.
/// `com.example.app.openai`). Items are flagged
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and never sync to iCloud.
///
/// The default `servicePrefix` is the host app's bundle identifier. Pass an
/// explicit prefix when the kit is used in a context without a usable bundle
/// id (unit tests, command-line tools, app extensions sharing a Keychain
/// access group, etc.).
public actor KeychainTokenStorage: TokenStorage {
    public let servicePrefix: String

    public init(servicePrefix: String? = nil) {
        self.servicePrefix = servicePrefix
            ?? Bundle.main.bundleIdentifier
            ?? "com.codingplan.auth"
    }

    public func save(credentials: Credentials, for providerId: String) async throws {
        let data = try JSONEncoder().encode(credentials)
        let query = baseQuery(for: providerId)

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let updateQuery: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, updateQuery as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw AuthError.storageError("Failed to update keychain item: \(updateStatus)")
            }
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AuthError.storageError("Failed to add keychain item: \(addStatus)")
            }
        }
    }

    public func load(for providerId: String) async throws -> Credentials? {
        var query = baseQuery(for: providerId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw AuthError.storageError("Failed to read keychain item: \(status)")
        }
        guard let data = result as? Data else {
            throw AuthError.storageError("Invalid keychain data")
        }
        return try JSONDecoder().decode(Credentials.self, from: data)
    }

    public func delete(for providerId: String) async throws {
        let query = baseQuery(for: providerId)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.storageError("Failed to delete keychain item: \(status)")
        }
    }

    // MARK: - Private

    private func baseQuery(for providerId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(servicePrefix).\(providerId)",
            kSecAttrAccount as String: providerId,
        ]
    }
}
