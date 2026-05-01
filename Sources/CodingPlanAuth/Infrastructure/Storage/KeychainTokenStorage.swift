// KeychainTokenStorage.swift
// CodingPlanAuth

import Foundation
import Security

/// A ``TokenStorage`` implementation backed by the system Keychain.
///
/// Credentials are serialized as JSON and stored under a service name derived
/// from ``servicePrefix`` and the provider identifier (e.g.
/// `com.example.app.openai`). Items are flagged
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and never sync to iCloud.
///
/// The default `servicePrefix` is the host app's bundle identifier. In contexts
/// without a usable bundle id (unit tests, CLI tools, app-extension hosts where
/// `Bundle.main` is the host shell), the initializer throws so the caller is
/// forced to disambiguate — two CLIs sharing a process bundle would otherwise
/// silently share each other's credentials.
///
/// To share credentials with widget or other app extensions, configure a
/// shared Keychain Access Group in your entitlements and pass it as
/// ``accessGroup`` on every instance:
///
/// ```swift
/// let storage = try KeychainTokenStorage(accessGroup: "TEAMID.com.example.shared")
/// ```
public actor KeychainTokenStorage: TokenStorage {
    public let servicePrefix: String

    /// Optional `kSecAttrAccessGroup` value, e.g. `"TEAMID.com.example.shared"`.
    /// When set, credentials are stored in the shared Keychain Access Group so
    /// app extensions with the same entitlement can read them.
    public let accessGroup: String?

    /// - Throws: ``AuthError/storageError(_:)`` when `servicePrefix` is `nil`
    ///   and `Bundle.main.bundleIdentifier` is also `nil`. Pass an explicit
    ///   `servicePrefix` from CLI tools, test harnesses, and any other host
    ///   without a unique bundle identifier.
    public init(servicePrefix: String? = nil, accessGroup: String? = nil) throws {
        if let servicePrefix {
            self.servicePrefix = servicePrefix
        } else if let bundleId = Bundle.main.bundleIdentifier {
            self.servicePrefix = bundleId
        } else {
            throw AuthError.storageError(
                "KeychainTokenStorage requires an explicit servicePrefix when Bundle.main has no bundle identifier (CLI / test contexts)."
            )
        }
        self.accessGroup = accessGroup
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
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(servicePrefix).\(providerId)",
            kSecAttrAccount as String: providerId,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
