# CodingPlanKit

Umbrella Swift package for working with AI coding-plan accounts on iOS 17+ /
macOS 14+. Sign users in with OAuth 2.0 + PKCE, persist credentials in the
Keychain, and call plan-bound APIs that charge the user's plan instead of
your API key — no per-token billing.

The package ships **two products** (more to come):

| Product | Purpose | Depends on |
|---|---|---|
| `CodingPlanAuth` | OAuth + token storage. Pure auth. | `SwiftWebServer` |
| `CodingPlanCodex` | Plan-bound API clients (Codex chat, usage / quota). | `CodingPlanAuth` |

Pick `CodingPlanAuth` alone if you only need OAuth. Add `CodingPlanCodex`
when you also want to call the ChatGPT backend.

**`CodingPlanAuth`**

- iOS 17+ / macOS 14+, Swift 6 with strict concurrency
- OAuth 2.0 + PKCE, Keychain-backed token storage (App Group ready)
- Pluggable provider registry (Strategy pattern) for adding Anthropic / Google later
- Generic `OAuth2PKCEFlow` engine — a new provider is `OAuthConfig` + a `OAuth2TokenResponseParser`

**`CodingPlanCodex`**

- Buffered Codex chat (`createTextResponse`) and live streaming
  (`streamTextResponse` returning `AsyncThrowingStream<String>`) via `URLSession.bytes(for:)`
- Plan-bound usage / rate-limit snapshot (`OpenAICodexUsageClient.fetchRateLimits`)
- Structured `CodexError` distinguishing HTTP-status failures from SSE-event failures

## Install

In `Package.swift`:

```swift
.package(url: "https://github.com/atom2ueki/CodingPlanKit.git", from: "0.1.0"),
```

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "CodingPlanAuth", package: "CodingPlanKit"),
        .product(name: "CodingPlanCodex", package: "CodingPlanKit"),
    ]
)
```

For iOS, register a custom URL scheme in `Info.plist` (e.g. `myapp`) so
`ASWebAuthenticationSession` can return cleanly from the OAuth redirect.

## Quick start (SwiftUI)

```swift
import SwiftUI
import CodingPlanAuth

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

## Documentation

Full architecture, types, and "how to add a provider" are in the DocC catalogs
([`CodingPlanAuth`](Sources/CodingPlanAuth/Documentation.docc/CodingPlanAuth.md),
[`CodingPlanCodex`](Sources/CodingPlanCodex/Documentation.docc/CodingPlanCodex.md))
and in [`llms.txt`](./llms.txt) for AI agents.

## Testing

```sh
swift test
```

Covers OAuth URL building, token-response parsing, refresh behavior, the
Keychain storage actor, the local callback server (real ports), and the
Codex / usage clients via injected `HTTPClient` mocks.

## License

[MIT](./LICENSE) © 2026 Tony Li
