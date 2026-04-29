import Foundation
import Testing
@testable import CodingPlanAuth

struct OpenAIAuthProviderTests {
    @Test
    func authorizationURLUsesCodexRedirectAndParameters() throws {
        let url = try OAuth2PKCEFlow.authorizationURL(
            config: OpenAIOAuthConfig.default(),
            redirectURI: "http://localhost:1455/auth/callback",
            state: "state-123",
            pkce: PKCE(verifier: "verifier", challenge: "challenge")
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(components.host == "auth.openai.com")
        #expect(components.path == "/oauth/authorize")
        #expect(params["client_id"] == "app_EMoamEEZ73f0CkXaXp7hrann")
        #expect(params["response_type"] == "code")
        #expect(params["scope"] == "openid profile email offline_access api.connectors.read api.connectors.invoke")
        #expect(params["code_challenge_method"] == "S256")
        #expect(params["state"] == "state-123")
        #expect(params["code_challenge"] == "challenge")
        #expect(params["redirect_uri"] == "http://localhost:1455/auth/callback")
        #expect(params["id_token_add_organizations"] == "true")
        #expect(params["codex_cli_simplified_flow"] == "true")
        #expect(params["originator"] == "codex_cli_rs")
        #expect(!url.absoluteString.contains("localhost:0"))
    }

    @Test
    func completeLoginWithCustomSchemeBypassesServer() async throws {
        let tokenJSON = """
        {
            "access_token": "new_access_token",
            "refresh_token": "new_refresh_token",
            "expires_in": 3600,
            "token_type": "Bearer"
        }
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
        await httpClient.setResponse(for: tokenURL, data: tokenJSON, statusCode: 200)

        let provider = OpenAIAuthProvider(
            httpClient: httpClient,
            config: OpenAIOAuthConfig.default(redirectPort: 15456)
        )
        let session = try await provider.beginLogin()
        let comps = URLComponents(url: session.authURL, resolvingAgainstBaseURL: false)
        let state = comps?.queryItems?.first(where: { $0.name == "state" })?.value ?? ""
        
        // Use a custom scheme callback to bypass the real server.
        let callbackURL = URL(string: "myapp://callback?code=authcode&state=\(state)")!
        let creds = try await session.complete(with: callbackURL)

        #expect(creds.accessToken == "new_access_token")
        #expect(creds.refreshToken == "new_refresh_token")
        #expect(creds.tokenType == "Bearer")
        #expect(creds.expiresAt != nil)
    }

    @Test
    func refreshTokenPreservesExistingRefreshTokenWhenOmitted() async throws {
        let tokenJSON = """
        {
            "access_token": "refreshed_token",
            "expires_in": 7200,
            "token_type": "Bearer"
        }
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
        await httpClient.setResponse(for: tokenURL, data: tokenJSON, statusCode: 200)

        let provider = OpenAIAuthProvider(httpClient: httpClient)
        let oldCreds = Credentials(
            accessToken: "old",
            refreshToken: "rt",
            expiresAt: Date().addingTimeInterval(-100)
        )
        let newCreds = try await provider.refresh(credentials: oldCreds)

        #expect(newCreds.accessToken == "refreshed_token")
        #expect(newCreds.refreshToken == "rt")

        let requests = await httpClient.recordedRequests()
        let request = try #require(requests.first)
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Accept"] == "application/json")

        let body = try #require(request.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["grant_type"] as? String == "refresh_token")
        #expect(json["refresh_token"] as? String == "rt")
        #expect(json["client_id"] as? String == "app_EMoamEEZ73f0CkXaXp7hrann")
    }

    @Test
    func parseTokenResponseUsesJWTExpirationWhenExpiresInIsOmitted() throws {
        let expiresAt = Date().addingTimeInterval(3600)
        let accessToken = try makeJWT(payload: [
            "exp": Int(expiresAt.timeIntervalSince1970),
        ])
        let tokenJSON = try JSONSerialization.data(withJSONObject: [
            "access_token": accessToken,
        ])

        let creds = try OpenAITokenResponseParser().parse(tokenJSON, fallbackRefreshToken: nil)

        let parsedExpiry = try #require(creds.expiresAt)
        #expect(abs(parsedExpiry.timeIntervalSince1970 - expiresAt.timeIntervalSince1970) < 1)
    }

    @Test
    func refreshTokenPreservesAccountMetadataWhenRefreshResponseOmitsIt() async throws {
        let accessToken = try makeJWT(payload: [
            "exp": Int(Date().addingTimeInterval(3600).timeIntervalSince1970),
        ])
        let tokenJSON = try JSONSerialization.data(withJSONObject: [
            "access_token": accessToken,
        ])

        let httpClient = MockHTTPClient()
        let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
        await httpClient.setResponse(for: tokenURL, data: tokenJSON, statusCode: 200)

        let provider = OpenAIAuthProvider(httpClient: httpClient)
        let oldCreds = Credentials(
            accessToken: "old",
            refreshToken: "rt",
            idToken: "old-id",
            expiresAt: Date().addingTimeInterval(-100),
            accountId: "account-123",
            accountEmail: "u@example.com",
            accountPlanType: "plus"
        )
        let newCreds = try await provider.refresh(credentials: oldCreds)

        #expect(newCreds.accessToken == accessToken)
        #expect(newCreds.refreshToken == "rt")
        #expect(newCreds.idToken == "old-id")
        #expect(newCreds.accountId == "account-123")
        #expect(newCreds.accountEmail == "u@example.com")
        #expect(newCreds.accountPlanType == "plus")
        #expect(newCreds.expiresAt != nil)
    }

    @Test
    func parseTokenResponseExtractsAccountInfoFromJWTClaims() throws {
        let accessToken = try makeJWT(payload: [
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acc-42",
                "chatgpt_plan_type": "plus",
            ],
        ])
        let idToken = try makeJWT(payload: [
            "email": "u@example.com",
        ])
        let tokenJSON = try JSONSerialization.data(withJSONObject: [
            "access_token": accessToken,
            "id_token": idToken,
            "expires_in": 3600,
        ])

        let creds = try OpenAITokenResponseParser().parse(tokenJSON, fallbackRefreshToken: nil)
        #expect(creds.accessToken == accessToken)
        #expect(creds.idToken == idToken)
        #expect(creds.accountId == "acc-42")
        #expect(creds.accountEmail == "u@example.com")
        #expect(creds.accountPlanType == "plus")
    }
}

private func makeJWT(payload: [String: Any]) throws -> String {
    let header = try JSONSerialization.data(withJSONObject: [
        "alg": "none",
        "typ": "JWT",
    ])
    let payloadData = try JSONSerialization.data(withJSONObject: payload)
    return [
        base64URLEncoded(header),
        base64URLEncoded(payloadData),
        "",
    ].joined(separator: ".")
}

private func base64URLEncoded(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
