# CodingPlanAuthKit

Sign in to AI coding-plan accounts (OpenAI Codex / ChatGPT today, more
providers tomorrow) from your iOS or macOS app, and reuse the resulting
plan-bound credentials to call the provider's APIs.

> Bring-your-own-account: users sign in with their existing Codex / ChatGPT
> plan, and your app inherits their quota. No API keys, no per-token billing.

- iOS 17+ / macOS 14+
- Swift 6, strict concurrency
- OAuth 2.0 + PKCE, tokens stored in the system Keychain
- Pure-Swift, dependency-light (uses [SwiftWebServer](https://github.com/) for the localhost callback)

## Install

In `Package.swift`:

```swift
.package(url: "https://github.com/atom2ueki/CodingPlanAuthKit.git", from: "0.1.0"),
```

```swift
.target(
    name: "MyApp",
    dependencies: [.product(name: "CodingPlanAuthKit", package: "CodingPlanAuthKit")]
)
```

For iOS, register a custom URL scheme in your `Info.plist` (e.g. `myapp`)
so `ASWebAuthenticationSession` can return cleanly from the OAuth redirect.

## Quick start (SwiftUI)

```swift
import SwiftUI
import CodingPlanAuthKit

@MainActor
@Observable
final class SignIn {
    private let service = AuthService(storage: KeychainTokenStorage())
    private let provider = OpenAIAuthProvider(callbackScheme: "myapp")
    private let browser = BrowserAuthSession()
    var credentials: Credentials?

    func signIn() async throws {
        await service.register(provider)
        let session = try await service.beginLogin(providerId: "openai")
        let callbackURL = try await browser.authenticate(
            url: session.authURL,
            callbackScheme: "myapp"
        )
        credentials = try await service.completeLogin(
            session: session,
            with: callbackURL,
            providerId: "openai"
        )
    }
}
```

Once signed in, call the provider's APIs with the credentials:

```swift
let codex = OpenAICodexClient()
let answer = try await codex.createTextResponse(
    prompt: "Refactor this Swift function...",
    credentials: credentials
)
```

## Architecture

CodingPlanAuthKit is built around two patterns:

- **Hexagonal / Ports & Adapters** — the domain (`Core/`) defines protocols
  (`AuthProvider`, `TokenStorage`, `HTTPClient`); concrete adapters live in
  `Infrastructure/` and `Providers/`.
- **Strategy** — `AuthService` is a registry of `AuthProvider` strategies
  keyed by `id`; adding a new provider is a matter of writing one new adapter.

```
Sources/CodingPlanAuthKit/
├── Core/                       Domain protocols + value types (the "ports")
│   ├── AuthProvider.swift          ← protocol every provider implements
│   ├── TokenStorage.swift          ← protocol for credential persistence
│   ├── Credentials.swift           ← OAuth tokens + plan/account metadata
│   └── AuthError.swift             ← typed errors (LocalizedError)
│
├── Application/                Use cases / orchestration
│   └── AuthService.swift           ← actor; registers providers, refreshes tokens
│
├── Presentation/               UI integration (SwiftUI / AppKit / UIKit)
│   ├── AuthState.swift             ← @Observable view-model glue
│   └── BrowserAuthSession.swift    ← ASWebAuthenticationSession wrapper
│
├── Infrastructure/             Generic adapters (the "driven" side)
│   ├── HTTP/HTTPClient.swift       ← URLSession HTTP transport
│   ├── OAuth/OAuthConfig.swift     ← provider-agnostic OAuth config
│   ├── OAuth/PKCE.swift            ← S256 PKCE generator
│   ├── Server/LocalCallbackServer.swift  ← localhost OAuth redirect server
│   └── Storage/KeychainTokenStorage.swift ← Keychain-backed TokenStorage
│
└── Providers/                  Provider-specific adapters (the "driving" side)
    └── OpenAI/
        ├── Auth/                   ← OAuth handshake + JWT claim parsing
        │   ├── OpenAIAuthProvider.swift
        │   ├── OpenAILoginSession.swift
        │   ├── OpenAIOAuthConfig.swift
        │   └── OpenAITokenResponseParser.swift
        └── API/                    ← Plan-bound API clients
            ├── OpenAICodexClient.swift
            └── OpenAICodexUsageClient.swift
```

### Adding a new provider

1. Create `Providers/<Name>/Auth/<Name>AuthProvider.swift` conforming to
   `AuthProvider`.
2. Reuse `OAuthConfig`, `PKCE`, `LocalCallbackServer`, and `HTTPClient` from
   `Infrastructure/`.
3. Optionally add `Providers/<Name>/API/` clients that consume `Credentials`.
4. Register it: `await service.register(MyProvider())`.

## Testing

```sh
swift test
```

The test suite covers OAuth URL building, token-response parsing, refresh
behavior, the Keychain storage actor, the local callback server (real
ports), and the Codex / usage clients via injected `HTTPClient` mocks.

## License

[MIT](./LICENSE) © 2026 Tony Li
