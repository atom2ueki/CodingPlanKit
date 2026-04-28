// AuthProvider.swift
// CodingPlanAuthKit

import Foundation

/// A login session produced by an ``AuthProvider``.
///
/// The session encapsulates ephemeral state (PKCE, state param) required to
/// complete the OAuth handshake. The caller is responsible for opening the
/// ``authURL`` in a browser and delivering the resulting callback URL to
/// ``complete(with:)``.
public protocol LoginSession: Sendable {
    /// The provider this session belongs to (matches ``AuthProvider/id``).
    var providerId: String { get }

    /// The URL to present in the browser.
    var authURL: URL { get }

    /// Complete the login using the URL returned by the OAuth redirect.
    func complete(with callbackURL: URL) async throws -> Credentials

    /// Cancel any ephemeral resources created for the login flow.
    func cancel() async
}

public extension LoginSession {
    func cancel() async {}
}

/// A provider-specific authentication backend.
///
/// Conformers must be `Sendable` and safe to call from multiple concurrent
/// isolation domains.
public protocol AuthProvider: Sendable {
    /// A stable identifier for this provider, e.g. `"openai"`.
    var id: String { get }

    /// A human-readable name, e.g. `"OpenAI"`.
    var name: String { get }

    /// Begin a new login flow.
    ///
    /// Returns a ``LoginSession`` containing the URL to open in a browser.
    func beginLogin() async throws -> any LoginSession

    /// Refresh credentials using a stored refresh token.
    func refresh(credentials: Credentials) async throws -> Credentials
}
