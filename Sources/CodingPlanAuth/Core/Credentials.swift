// Credentials.swift
// CodingPlanAuth

import Foundation

/// OAuth credentials plus optional plan/account metadata returned by a provider.
public struct Credentials: Codable, Sendable, Equatable {
    /// The OAuth access token. Pass as `Authorization: Bearer <accessToken>`.
    public let accessToken: String

    /// Refresh token used to obtain a new access token when this one expires.
    public let refreshToken: String?

    /// ID token (JWT) when the provider returns one alongside the access token.
    public let idToken: String?

    /// Wall-clock instant after which ``accessToken`` is no longer valid.
    public let expiresAt: Date?

    /// Token scheme; almost always ``TokenType/bearer``.
    public let tokenType: TokenType

    /// Provider-side account identifier extracted from JWT claims (e.g. `chatgpt_account_id`).
    public let accountId: String?

    /// Account email extracted from JWT claims, when available.
    public let accountEmail: String?

    /// Plan type label from JWT claims (e.g. `"plus"`, `"team"`).
    public let accountPlanType: String?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        idToken: String? = nil,
        expiresAt: Date? = nil,
        tokenType: TokenType = .bearer,
        accountId: String? = nil,
        accountEmail: String? = nil,
        accountPlanType: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.expiresAt = expiresAt
        self.tokenType = tokenType
        self.accountId = accountId
        self.accountEmail = accountEmail
        self.accountPlanType = accountPlanType
    }

    /// Returns `true` if the access token is considered expired.
    ///
    /// - Parameter leeway: Seconds of slack subtracted from ``expiresAt`` to
    ///   absorb clock skew between client and server. Defaults to 60.
    public func isExpired(leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(leeway) >= expiresAt
    }

    /// Returns `true` if the access token is considered expired with the
    /// default 60-second leeway.
    public var isExpired: Bool {
        isExpired()
    }
}
