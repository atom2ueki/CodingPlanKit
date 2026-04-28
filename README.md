# CodingPlanAuthKit

OAuth 2.0 + PKCE for AI coding-plan accounts (OpenAI Codex / ChatGPT today,
more providers next) on iOS 17+ / macOS 14+. Sign users into their existing
plan, persist credentials in the Keychain, and let your app inherit their
quota — no API keys, no per-token billing.

The package ships **two products**:

| Product | Purpose | Depends on |
|---|---|---|
| `CodingPlanAuthKit` | OAuth + token storage. Pure auth. | `SwiftWebServer` |
| `CodingPlanCodex` | Plan-bound API clients (Codex chat, usage / quota). | `CodingPlanAuthKit` |

Pick `CodingPlanAuthKit` alone if you only need OAuth. Add `CodingPlanCodex`
when you also want to call the ChatGPT backend.

- iOS 17+ / macOS 14+, Swift 6 with strict concurrency
- OAuth 2.0 + PKCE, Keychain-backed token storage (App Group ready)
- Pluggable provider registry (Strategy pattern) for adding Anthropic / Google later
- Buffered + streaming Codex API clients (live `AsyncThrowingStream<String>` deltas)

## Install

In `Package.swift`:

```swift
.package(url: "https://github.com/atom2ueki/CodingPlanAuthKit.git", from: "0.1.0"),
```

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "CodingPlanAuthKit", package: "CodingPlanAuthKit"),
        // .product(name: "CodingPlanCodex", package: "CodingPlanAuthKit"),  // optional
    ]
)
```

For iOS, register a custom URL scheme in `Info.plist` (e.g. `myapp`) so
`ASWebAuthenticationSession` can return cleanly from the OAuth redirect.

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
            with: callbackURL
        )
    }
}
```

Once signed in, call plan-bound APIs with `CodingPlanCodex`:

```swift
import CodingPlanCodex

let codex = OpenAICodexClient()

// One-shot:
let response = try await codex.createTextResponse(
    prompt: "Refactor this Swift function...",
    credentials: credentials
)

// Or stream deltas as they arrive:
for try await delta in codex.streamTextResponse(prompt: "...", credentials: credentials) {
    print(delta, terminator: "")
}
```

## Architecture

`CodingPlanAuthKit` is built around two patterns:

- **Hexagonal / Ports & Adapters** — `Core/` defines protocols
  (`AuthProvider`, `TokenStorage`, `HTTPClient`, `LoginSession`); concrete
  adapters live in `Infrastructure/` and `Providers/`.
- **Strategy** — `AuthService` is a registry of `AuthProvider` strategies
  keyed by `id`. A new provider is a config + a `OAuth2TokenResponseParser`.

```
Sources/
├── CodingPlanAuthKit/                  ← OAuth + storage
│   ├── Core/                               Domain protocols + value types
│   │   ├── AuthProvider.swift
│   │   ├── LoginSession.swift              (in AuthProvider.swift)
│   │   ├── TokenStorage.swift
│   │   ├── Credentials.swift
│   │   ├── TokenType.swift
│   │   └── AuthError.swift
│   ├── Application/AuthService.swift   ← actor registry
│   ├── Presentation/
│   │   ├── AuthState.swift             ← @Observable for SwiftUI
│   │   └── BrowserAuthSession.swift    ← ASWebAuthenticationSession wrapper
│   ├── Infrastructure/
│   │   ├── HTTP/HTTPClient.swift       ← typed buffered + streaming HTTP
│   │   ├── OAuth/OAuthConfig.swift
│   │   ├── OAuth/PKCE.swift
│   │   ├── OAuth/OAuth2PKCEFlow.swift  ← reusable OAuth2 + PKCE engine
│   │   ├── OAuth/OAuth2LoginSession.swift
│   │   ├── OAuth/OAuth2TokenResponseParser.swift
│   │   ├── OAuth/OAuth2Helpers.swift
│   │   ├── Server/LocalCallbackServer.swift
│   │   └── Storage/KeychainTokenStorage.swift  ← App-Group ready
│   ├── Providers/OpenAI/Auth/          ← OpenAI-specific config + JWT parser
│   │   ├── OpenAIAuthProvider.swift        (~50 LOC; wraps OAuth2PKCEFlow)
│   │   ├── OpenAIOAuthConfig.swift
│   │   └── OpenAITokenResponseParser.swift
│   └── Documentation.docc/             ← DocC catalog
│
└── CodingPlanCodex/                    ← Plan-bound API clients
    ├── OpenAIBackend.swift                 backend constants
    ├── OpenAICodexClient.swift             buffered + streaming
    ├── OpenAICodexUsageClient.swift        rate-limit / quota
    ├── CodexError.swift                    structured backend errors
    └── Documentation.docc/
```

### Adding a new provider

`OAuth2PKCEFlow` handles PKCE, the local callback server, the authorization
URL, auth-code exchange, and refresh — so a new provider is essentially
**a config + a token-response parser**:

```swift
public struct AnthropicTokenResponseParser: OAuth2TokenResponseParser { … }

public actor AnthropicAuthProvider: AuthProvider {
    public let id = "anthropic"
    public let name = "Anthropic"
    private let flow: OAuth2PKCEFlow

    public init(callbackScheme: String? = nil) {
        self.flow = OAuth2PKCEFlow(
            providerId: "anthropic",
            config: AnthropicOAuthConfig.default(),
            parser: AnthropicTokenResponseParser(),
            callbackScheme: callbackScheme
        )
    }

    public func beginLogin() async throws -> any LoginSession {
        try await flow.beginLogin()
    }

    public func refresh(credentials: Credentials) async throws -> Credentials {
        try await flow.refresh(credentials: credentials)
    }
}
```

## Testing

```sh
swift test
```

Covers OAuth URL building, token-response parsing, refresh behavior, the
Keychain storage actor, the local callback server (real ports), and the
Codex / usage clients via injected `HTTPClient` mocks.

## License

[MIT](./LICENSE) © 2026 Tony Li
