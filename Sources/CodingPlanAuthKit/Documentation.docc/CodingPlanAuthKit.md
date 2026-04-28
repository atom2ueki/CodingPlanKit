@Metadata {
    @DisplayName("CodingPlanAuthKit")
}

# ``CodingPlanAuthKit``

OAuth 2.0 + PKCE for AI coding-plan accounts on iOS 17+ / macOS 14+.

## Overview

`CodingPlanAuthKit` lets your app sign users into their existing AI plan
account (OpenAI today, others next) and persists the resulting credentials
in the system Keychain. Subsequent API calls use the user's plan rather than
your API key.

The kit is structured as **Hexagonal / Ports & Adapters** with a Strategy
registry: domain protocols in ``AuthProvider``, ``TokenStorage``,
``HTTPClient``, ``LoginSession``; concrete adapters in `Infrastructure/`
and `Providers/`; ``AuthService`` is the registry that orchestrates them.

A typical SwiftUI flow:

```swift
import CodingPlanAuthKit

@MainActor @Observable
final class SignIn {
    private let service = AuthService(storage: KeychainTokenStorage())
    private let provider = OpenAIAuthProvider(callbackScheme: "myapp")
    private let browser = BrowserAuthSession()
    var credentials: Credentials?

    func signIn() async throws {
        await service.register(provider)
        let session = try await service.beginLogin(providerId: "openai")
        let callback = try await browser.authenticate(
            url: session.authURL, callbackScheme: "myapp"
        )
        credentials = try await service.completeLogin(session: session, with: callback)
    }
}
```

To call plan-bound APIs after sign-in, add the sibling product
`CodingPlanCodex`.

## Topics

### Domain

- ``AuthProvider``
- ``LoginSession``
- ``TokenStorage``
- ``Credentials``
- ``TokenType``
- ``AuthError``

### Orchestration

- ``AuthService``
- ``AuthState``

### Browser

- ``BrowserAuthSession``

### OAuth 2.0 + PKCE engine

- ``OAuth2PKCEFlow``
- ``OAuth2TokenResponseParser``
- ``OAuth2RefreshBodyEncoding``
- ``OAuthConfig``
- ``PKCE``

### HTTP transport

- ``HTTPClient``
- ``URLSessionHTTPClient``
- ``HTTPRequest``
- ``HTTPResponse``
- ``HTTPStreamingResponse``
- ``HTTPMethod``

### Storage

- ``KeychainTokenStorage``

### OpenAI provider

- ``OpenAIAuthProvider``
- ``OpenAIOAuthConfig``
- ``OpenAITokenResponseParser``
