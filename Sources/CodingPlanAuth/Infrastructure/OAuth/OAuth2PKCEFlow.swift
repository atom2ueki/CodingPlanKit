// OAuth2PKCEFlow.swift
// CodingPlanAuth
//
// Reusable engine for OAuth 2.0 authorization-code + PKCE flows
// (RFC 6749 §4.1 with RFC 7636). Adapter providers (OpenAI today,
// Anthropic / Google tomorrow) wrap this and inject only their
// configuration plus an ``OAuth2TokenResponseParser`` for their own
// JWT claim shapes.

import Foundation

/// Body encoding used for the token-refresh grant. Auth-code exchange
/// always uses form-urlencoded per RFC 6749, but the refresh grant body
/// shape varies between providers.
public enum OAuth2RefreshBodyEncoding: Sendable {
    /// `application/x-www-form-urlencoded` — the spec-compliant default,
    /// used by most providers.
    case formURLEncoded
    /// `application/json` — used by OpenAI's token endpoint.
    case json
}

/// Generic OAuth 2.0 + PKCE flow engine.
public actor OAuth2PKCEFlow {
    public let providerId: String
    public let config: OAuthConfig
    public let parser: any OAuth2TokenResponseParser
    public let callbackScheme: String?
    public let defaultPort: UInt16
    public let callbackPath: String
    public let refreshBodyEncoding: OAuth2RefreshBodyEncoding

    private let httpClient: any HTTPClient

    /// Create a new flow.
    ///
    /// - Parameters:
    ///   - providerId: Identifier propagated onto the resulting ``LoginSession``
    ///     and used by ``AuthService`` to key persisted credentials.
    ///   - config: The provider's OAuth endpoints, client id, and scopes.
    ///   - parser: How to decode the provider's JWT-bearing token response.
    ///   - httpClient: HTTP transport. Defaults to ``URLSessionHTTPClient``.
    ///   - callbackScheme: Optional custom URL scheme. When set, the local
    ///     callback server redirects to `<scheme>://auth/callback` so
    ///     `ASWebAuthenticationSession` can intercept and dismiss cleanly.
    ///   - defaultPort: Fallback localhost port when ``OAuthConfig/redirectURI``
    ///     doesn't specify one or specifies `0`. Pass `0` to let the OS pick.
    ///   - callbackPath: Path served by the local callback server.
    ///   - refreshBodyEncoding: How the provider expects refresh-grant bodies.
    public init(
        providerId: String,
        config: OAuthConfig,
        parser: any OAuth2TokenResponseParser,
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        callbackScheme: String? = nil,
        defaultPort: UInt16 = 0,
        callbackPath: String = "/auth/callback",
        refreshBodyEncoding: OAuth2RefreshBodyEncoding = .formURLEncoded
    ) {
        self.providerId = providerId
        self.config = config
        self.parser = parser
        self.httpClient = httpClient
        self.callbackScheme = callbackScheme
        self.defaultPort = defaultPort
        self.callbackPath = callbackPath
        self.refreshBodyEncoding = refreshBodyEncoding
    }

    /// Begin an authorization-code + PKCE handshake. Returns a session
    /// whose ``LoginSession/authURL`` the caller must open in a browser.
    public func beginLogin() async throws -> any LoginSession {
        let pkce = PKCE.generate()
        let state = randomState()
        let serverPort = redirectPort(from: config.redirectURI)
            .flatMap { $0 > 0 ? $0 : nil }
            ?? defaultPort

        let redirectBaseURL: String? = callbackScheme.map { "\($0)://auth/callback" }

        let server = LocalCallbackServer(
            port: serverPort,
            callbackPath: callbackPath,
            redirectBaseURL: redirectBaseURL
        )
        let serverTask = Task { try await server.start() }
        let actualPort: UInt16
        do {
            actualPort = try await server.waitUntilStarted()
        } catch {
            serverTask.cancel()
            await server.stop()
            throw error
        }
        let redirectURI = "http://localhost:\(actualPort)\(callbackPath)"

        let authURL = try Self.authorizationURL(
            config: config,
            redirectURI: redirectURI,
            state: state,
            pkce: pkce
        )

        return OAuth2LoginSession(
            providerId: providerId,
            authURL: authURL,
            state: state,
            pkceVerifier: pkce.verifier,
            redirectURI: redirectURI,
            server: server,
            clientId: config.clientId,
            tokenEndpoint: config.tokenEndpoint,
            httpClient: httpClient,
            parser: parser
        )
    }

    /// Exchange a refresh token for a fresh credentials triple.
    public func refresh(credentials: Credentials) async throws -> Credentials {
        guard let refreshToken = credentials.refreshToken else {
            throw AuthError.tokenExchangeFailed(statusCode: nil, message: "No refresh token available")
        }

        let params: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId,
        ]

        let request: HTTPRequest
        switch refreshBodyEncoding {
        case .formURLEncoded:
            let body = formURLEncoded(params)
            request = HTTPRequest(
                url: config.tokenEndpoint,
                method: .post,
                headers: [
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Accept": "application/json",
                ],
                body: Data(body.utf8)
            )
        case .json:
            let body = try JSONSerialization.data(withJSONObject: params)
            request = HTTPRequest(
                url: config.tokenEndpoint,
                method: .post,
                headers: [
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                ],
                body: body
            )
        }

        let response = try await httpClient.send(request)
        guard response.isSuccess else {
            let message = String(data: response.body, encoding: .utf8) ?? "Unknown error"
            throw AuthError.tokenExchangeFailed(statusCode: response.statusCode, message: message)
        }

        let refreshed = try parser.parse(response.body, fallbackRefreshToken: refreshToken)
        return Credentials(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            idToken: refreshed.idToken ?? credentials.idToken,
            expiresAt: refreshed.expiresAt,
            tokenType: refreshed.tokenType,
            accountId: refreshed.accountId ?? credentials.accountId,
            accountEmail: refreshed.accountEmail ?? credentials.accountEmail,
            accountPlanType: refreshed.accountPlanType ?? credentials.accountPlanType
        )
    }

    /// Build the authorization URL per RFC 6749 §4.1.1 + RFC 7636.
    /// Exposed for testing and for providers that want to drive the flow
    /// outside this engine (e.g. WebView-based callers).
    public static func authorizationURL(
        config: OAuthConfig,
        redirectURI: String,
        state: String,
        pkce: PKCE
    ) throws -> URL {
        guard var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw AuthError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
        ] + config.additionalParameters.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let authURL = components.url else {
            throw AuthError.invalidURL
        }
        return authURL
    }

    private nonisolated func redirectPort(from redirectURI: String) -> UInt16? {
        guard let url = URL(string: redirectURI), let port = url.port else { return nil }
        return UInt16(port)
    }
}
