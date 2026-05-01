// OAuth2LoginSession.swift
// CodingPlanAuth
//
// A reusable ``LoginSession`` produced by ``OAuth2PKCEFlow``. Holds the
// ephemeral state for one in-flight handshake and exchanges the
// authorization code for credentials when the browser callback returns.

import Foundation

actor OAuth2LoginSession: LoginSession {
    nonisolated let providerId: String
    nonisolated let authURL: URL
    private let state: String
    private let pkceVerifier: String
    private let redirectURI: String
    private let server: LocalCallbackServer
    private let clientId: String
    private let tokenEndpoint: URL
    private let httpClient: any HTTPClient
    private let parser: any OAuth2TokenResponseParser

    init(
        providerId: String,
        authURL: URL,
        state: String,
        pkceVerifier: String,
        redirectURI: String,
        server: LocalCallbackServer,
        clientId: String,
        tokenEndpoint: URL,
        httpClient: any HTTPClient,
        parser: any OAuth2TokenResponseParser
    ) {
        self.providerId = providerId
        self.authURL = authURL
        self.state = state
        self.pkceVerifier = pkceVerifier
        self.redirectURI = redirectURI
        self.server = server
        self.clientId = clientId
        self.tokenEndpoint = tokenEndpoint
        self.httpClient = httpClient
        self.parser = parser
    }

    func complete(with callbackURL: URL) async throws -> Credentials {
        // Extract params from the callback URL directly. Works for both
        // localhost-intercepted-by-WKWebView and custom-scheme callbacks.
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw AuthError.missingAuthorizationCode
        }
        let returnedState = items.first(where: { $0.name == "state" })?.value
        let params = CallbackParameters(code: code, state: returnedState)

        await server.stop()

        guard params.state == state else {
            throw AuthError.invalidState
        }

        let body = formURLEncoded([
            "grant_type": "authorization_code",
            "code": params.code,
            "redirect_uri": redirectURI,
            "client_id": clientId,
            "code_verifier": pkceVerifier,
        ])

        let response = try await httpClient.send(HTTPRequest(
            url: tokenEndpoint,
            method: .post,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(body.utf8)
        ))

        guard response.isSuccess else {
            let message = String(data: response.body, encoding: .utf8) ?? "Unknown error"
            throw AuthError.tokenExchangeFailed(statusCode: response.statusCode, message: message)
        }

        return try parser.parse(response.body, fallbackRefreshToken: nil)
    }

    func cancel() async {
        await server.stop()
    }
}
