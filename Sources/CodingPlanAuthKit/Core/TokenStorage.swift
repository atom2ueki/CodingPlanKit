// TokenStorage.swift
// CodingPlanAuthKit

import Foundation

/// A storage backend for persisting and retrieving credentials.
public protocol TokenStorage: Sendable {
    /// Save credentials for a given provider.
    func save(credentials: Credentials, for providerId: String) async throws

    /// Load credentials for a given provider, if any.
    func load(for providerId: String) async throws -> Credentials?

    /// Delete stored credentials for a given provider.
    func delete(for providerId: String) async throws
}
