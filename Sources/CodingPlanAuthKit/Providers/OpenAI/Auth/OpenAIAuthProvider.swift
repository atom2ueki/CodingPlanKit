// OpenAIAuthProvider.swift
// CodingPlanAuthKit
//
// Concrete ``AuthProvider`` adapter for OpenAI / ChatGPT coding plans.
//
// Wraps the generic OAuth 2.0 + PKCE handshake with the OpenAI-specific
// authorization endpoint, default scopes, and JWT claim parsing.

import Foundation

public actor OpenAIAuthProvider: AuthProvider {
    public let id = "openai"
    public let name = "OpenAI"

    private let httpClient: any HTTPClient
    private let config: OAuthConfig
    private let callbackScheme: String?

    /// Create a new OpenAI auth provider.
    ///
    /// - Parameters:
    ///   - httpClient: The HTTP transport. Defaults to `URLSessionHTTPClient`.
    ///   - config: OAuth configuration. Defaults to ``OpenAIOAuthConfig/default(redirectPort:originator:)``.
    ///   - callbackScheme: Optional custom URL scheme. When provided, the
    ///     local callback server redirects to `<scheme>://auth/callback` so
    ///     `ASWebAuthenticationSession` can intercept and dismiss cleanly.
    public init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        config: OAuthConfig = OpenAIOAuthConfig.default(),
        callbackScheme: String? = nil
    ) {
        self.httpClient = httpClient
        self.config = config
        self.callbackScheme = callbackScheme
    }

    public func beginLogin() async throws -> any LoginSession {
        let pkce = PKCE.generate()
        let state = randomState()
        let configuredPort = redirectPort(from: config.redirectURI)
        let serverPort = (configuredPort ?? 0) > 0 ? configuredPort! : OpenAIOAuthConfig.defaultCallbackPort

        let redirectBaseURL: String? = callbackScheme.map { "\($0)://auth/callback" }

        let server = LocalCallbackServer(
            port: serverPort,
            callbackPath: OpenAIOAuthConfig.callbackPath,
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
        let redirectURI = "http://localhost:\(actualPort)\(OpenAIOAuthConfig.callbackPath)"

        let authURL = try Self.authorizationURL(
            config: config,
            redirectURI: redirectURI,
            state: state,
            pkce: pkce
        )

        return OpenAILoginSession(
            providerId: id,
            authURL: authURL,
            state: state,
            pkceVerifier: pkce.verifier,
            redirectURI: redirectURI,
            serverTask: serverTask,
            server: server,
            clientId: config.clientId,
            tokenEndpoint: config.tokenEndpoint,
            httpClient: httpClient
        )
    }

    public func refresh(credentials: Credentials) async throws -> Credentials {
        guard let refreshToken = credentials.refreshToken else {
            throw AuthError.tokenExchangeFailed("No refresh token available")
        }

        let requestBody: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId,
        ]
        let body = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await httpClient.request(
            url: config.tokenEndpoint,
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json",
            ],
            body: body
        )

        guard (200..<300).contains(response.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.tokenExchangeFailed(message)
        }

        let refreshed = try Self.parseTokenResponse(data, fallbackRefreshToken: refreshToken)
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

    // MARK: - Static helpers (also used by tests)

    static func authorizationURL(
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

    static func parseTokenResponse(_ data: Data, fallbackRefreshToken: String? = nil) throws -> Credentials {
        try OpenAITokenResponseParser.parse(data, fallbackRefreshToken: fallbackRefreshToken)
    }

    // MARK: - Private

    private func redirectPort(from redirectURI: String) -> UInt16? {
        guard let url = URL(string: redirectURI),
              let port = url.port else { return nil }
        return UInt16(port)
    }
}

func randomState(length: Int = 32) -> String {
    let alphabet: [Character] = Array(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )
    var rng = SystemRandomNumberGenerator()
    return String((0..<length).map { _ in
        alphabet[Int.random(in: 0..<alphabet.count, using: &rng)]
    })
}

func formURLEncoded(_ params: [String: String]) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")

    return params.map { key, value in
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
        let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return "\(encodedKey)=\(encodedValue)"
    }.joined(separator: "&")
}
