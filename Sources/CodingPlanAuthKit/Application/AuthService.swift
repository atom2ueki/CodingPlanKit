// AuthService.swift
// CodingPlanAuthKit

import Foundation

/// Orchestrates authentication across one or more providers.
///
/// `AuthService` is the registry side of the kit's Strategy pattern. Register
/// each provider you support, then drive the OAuth flow through this actor:
///
/// ```swift
/// let service = AuthService(storage: KeychainTokenStorage())
/// await service.register(OpenAIAuthProvider(callbackScheme: "myapp"))
/// let session = try await service.beginLogin(providerId: "openai")
/// // ... present session.authURL in a browser, receive callback URL ...
/// let creds = try await service.completeLogin(session: session, with: callbackURL)
/// ```
///
/// All mutable state is isolated to the actor. Safe to share across tasks.
public actor AuthService {
    private let storage: any TokenStorage
    private var providers: [String: any AuthProvider] = [:]

    /// Create a new service with the given storage backend.
    /// - Parameter storage: Where credentials are persisted.
    ///   Defaults to ``KeychainTokenStorage``.
    public init(storage: any TokenStorage = KeychainTokenStorage()) {
        self.storage = storage
    }

    /// Register an authentication provider, keyed by ``AuthProvider/id``.
    public func register(_ provider: any AuthProvider) {
        providers[provider.id] = provider
    }

    /// Returns `true` if credentials are stored for the given provider.
    /// Does not validate or refresh them.
    public func isAuthenticated(providerId: String) async throws -> Bool {
        let creds = try await storage.load(for: providerId)
        return creds != nil
    }

    /// Returns valid credentials for the provider, transparently refreshing
    /// them if the access token is expired.
    ///
    /// Returns `nil` when no credentials are stored.
    /// Throws ``AuthError/unsupportedProvider`` if the provider isn't registered.
    public func credentials(for providerId: String) async throws -> Credentials? {
        guard let provider = providers[providerId] else {
            throw AuthError.unsupportedProvider
        }
        guard var creds = try await storage.load(for: providerId) else {
            return nil
        }
        if creds.isExpired {
            creds = try await provider.refresh(credentials: creds)
            try await storage.save(credentials: creds, for: providerId)
        }
        return creds
    }

    /// Begin a login flow and return a ``LoginSession``.
    ///
    /// The caller must present ``LoginSession/authURL`` in a browser
    /// (typically via ``BrowserAuthSession``) and pass the resulting
    /// callback URL back to ``completeLogin(session:with:)``.
    public func beginLogin(providerId: String) async throws -> any LoginSession {
        guard let provider = providers[providerId] else {
            throw AuthError.unsupportedProvider
        }
        return try await provider.beginLogin()
    }

    /// Complete a login and persist the resulting credentials.
    ///
    /// The session knows which provider it belongs to via ``LoginSession/providerId``.
    public func completeLogin(
        session: any LoginSession,
        with callbackURL: URL
    ) async throws -> Credentials {
        guard providers[session.providerId] != nil else {
            throw AuthError.unsupportedProvider
        }
        let creds = try await session.complete(with: callbackURL)
        try await storage.save(credentials: creds, for: session.providerId)
        return creds
    }

    /// Remove stored credentials for the given provider.
    /// No-op if no credentials are present.
    public func logout(providerId: String) async throws {
        try await storage.delete(for: providerId)
    }
}
