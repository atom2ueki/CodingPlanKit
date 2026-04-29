// OpenAIOAuthConfig.swift
// CodingPlanAuth
//
// Pre-built OAuth configuration matching the official Codex CLI flow against
// `auth.openai.com`. Use ``OpenAIOAuthConfig/default(redirectPort:originator:)``
// directly, or pass a customized ``OAuthConfig`` to ``OpenAIAuthProvider``.

import Foundation

/// Pre-defined OpenAI OAuth configuration.
public enum OpenAIOAuthConfig {
    /// Default port used by the local OAuth callback server for OpenAI.
    public static let defaultCallbackPort: UInt16 = 1455

    /// Default callback path served by the local server.
    public static let callbackPath = "/auth/callback"

    private static let authorizationURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    private static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!

    /// The default production configuration used by Codex CLI.
    public static func `default`(
        redirectPort: UInt16 = OpenAIOAuthConfig.defaultCallbackPort,
        originator: String = "codex_cli_rs"
    ) -> OAuthConfig {
        OAuthConfig(
            clientId: "app_EMoamEEZ73f0CkXaXp7hrann",
            authorizationEndpoint: authorizationURL,
            tokenEndpoint: tokenURL,
            redirectURI: "http://localhost:\(redirectPort)\(OpenAIOAuthConfig.callbackPath)",
            scopes: [
                "openid",
                "profile",
                "email",
                "offline_access",
                "api.connectors.read",
                "api.connectors.invoke",
            ],
            additionalParameters: [
                "id_token_add_organizations": "true",
                "codex_cli_simplified_flow": "true",
                "originator": originator,
            ]
        )
    }
}
