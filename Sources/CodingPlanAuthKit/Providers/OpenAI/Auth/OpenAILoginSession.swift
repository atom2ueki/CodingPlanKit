// OpenAILoginSession.swift
// CodingPlanAuthKit
//
// Ephemeral state for one in-flight OpenAI OAuth handshake. Holds the PKCE
// verifier, expected `state`, the local callback server, and exchanges the
// authorization code for credentials when the browser callback returns.

import Foundation

actor OpenAILoginSession: LoginSession {
    nonisolated let providerId: String
    nonisolated let authURL: URL
    private let state: String
    private let pkceVerifier: String
    private let redirectURI: String
    private let serverTask: Task<CallbackParameters, any Error>
    private let server: LocalCallbackServer
    private let clientId: String
    private let tokenEndpoint: URL
    private let httpClient: any HTTPClient

    init(
        providerId: String,
        authURL: URL,
        state: String,
        pkceVerifier: String,
        redirectURI: String,
        serverTask: Task<CallbackParameters, any Error>,
        server: LocalCallbackServer,
        clientId: String,
        tokenEndpoint: URL,
        httpClient: any HTTPClient
    ) {
        self.providerId = providerId
        self.authURL = authURL
        self.state = state
        self.pkceVerifier = pkceVerifier
        self.redirectURI = redirectURI
        self.serverTask = serverTask
        self.server = server
        self.clientId = clientId
        self.tokenEndpoint = tokenEndpoint
        self.httpClient = httpClient
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

        let (data, response) = try await httpClient.request(
            url: tokenEndpoint,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(body.utf8)
        )

        guard (200..<300).contains(response.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.tokenExchangeFailed(message)
        }

        return try OpenAITokenResponseParser.parse(data)
    }

    func cancel() async {
        await server.stop()
    }
}
