// OpenAIAuthProvider.swift
// CodingPlanAuthKit
//
// Thin OpenAI / ChatGPT adapter on top of the generic ``OAuth2PKCEFlow``
// engine. The only OpenAI-specific bits are the OAuth config defaults,
// the localhost callback port, and the JWT claim parser that surfaces
// `chatgpt_account_id` / `chatgpt_plan_type` from the access token.

import Foundation

public actor OpenAIAuthProvider: AuthProvider {
    public let id = "openai"
    public let name = "OpenAI"

    private let flow: OAuth2PKCEFlow

    /// Create a new OpenAI auth provider.
    ///
    /// - Parameters:
    ///   - httpClient: HTTP transport. Defaults to ``URLSessionHTTPClient``.
    ///   - config: OAuth configuration. Defaults to ``OpenAIOAuthConfig/default(redirectPort:originator:)``.
    ///   - callbackScheme: Optional custom URL scheme. When provided, the
    ///     local callback server redirects to `<scheme>://auth/callback` so
    ///     `ASWebAuthenticationSession` can intercept and dismiss cleanly.
    public init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        config: OAuthConfig = OpenAIOAuthConfig.default(),
        callbackScheme: String? = nil
    ) {
        self.flow = OAuth2PKCEFlow(
            providerId: "openai",
            config: config,
            parser: OpenAITokenResponseParser(),
            httpClient: httpClient,
            callbackScheme: callbackScheme,
            defaultPort: OpenAIOAuthConfig.defaultCallbackPort,
            callbackPath: OpenAIOAuthConfig.callbackPath,
            refreshBodyEncoding: .json
        )
    }

    public func beginLogin() async throws -> any LoginSession {
        try await flow.beginLogin()
    }

    public func refresh(credentials: Credentials) async throws -> Credentials {
        try await flow.refresh(credentials: credentials)
    }
}
