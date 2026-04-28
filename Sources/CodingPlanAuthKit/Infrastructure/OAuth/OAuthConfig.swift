// OAuthConfig.swift
// CodingPlanAuthKit

import Foundation

/// Generic OAuth 2.0 configuration for an authorization-code + PKCE flow.
public struct OAuthConfig: Sendable, Equatable {
    public let clientId: String
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let redirectURI: String
    public let scopes: [String]
    public let additionalParameters: [String: String]

    public init(
        clientId: String,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        redirectURI: String,
        scopes: [String],
        additionalParameters: [String: String] = [:]
    ) {
        self.clientId = clientId
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.additionalParameters = additionalParameters
    }
}
