---
name: coding-plan-kit
description: Integrate the CodingPlanKit Swift package into iOS 17+ / macOS 14+ apps. Use when the user wants to (a) sign users in to ChatGPT/OpenAI with OAuth 2.0 + PKCE and persist credentials in the Keychain, or (b) call the Codex backend on the signed-in user's plan instead of charging an API key. Triggers on "CodingPlanKit", "CodingPlanAuth", "CodingPlanCodex", "plan-bound API", "ChatGPT login in iOS / SwiftUI", "Codex chat in Swift", "OpenAI OAuth in Swift", "AsyncThrowingStream Codex", "image generation Codex Swift", "fetch rate limits Codex Swift". Trigger even if the user just says "add CodingPlanKit" or pastes the GitHub URL.
---

# CodingPlanKit integration skill

CodingPlanKit is an umbrella Swift package (iOS 17+ / macOS 14+, Swift 6 strict
concurrency) that ships two SwiftPM products:

| Product | Purpose | Add when… |
|---|---|---|
| `CodingPlanAuth` | OAuth 2.0 + PKCE login, Keychain-backed credentials, pluggable provider registry. | The app needs to sign users in to ChatGPT (or any provider you add) and store tokens. |
| `CodingPlanCodex` | Plan-bound API clients on `chatgpt.com/backend-api` — Codex chat (buffered + streaming, with optional image generation), usage / rate limits, cloud tasks, environments, models, safety monitor. | You want to call the Codex backend using the signed-in user's plan, no API key. |

`CodingPlanCodex` depends on `CodingPlanAuth`. Pick `CodingPlanAuth` alone if
the app only needs OAuth.

## Authoritative reference

The repo ships an **`llms.txt`** at the root with full file-by-file index of
the public surface. Read it whenever the user asks for anything beyond the
patterns below:
<https://raw.githubusercontent.com/atom2ueki/CodingPlanKit/main/llms.txt>

DocC catalogs are also bundled inside both targets.

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

For an iOS app target, register a custom URL scheme in `Info.plist` (e.g.
`myapp`) so `ASWebAuthenticationSession` returns cleanly from the OAuth
redirect.

## Sign-in (SwiftUI, the canonical pattern)

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

    init() {
        Task { await service.register(provider) }
    }

    func signIn() async throws {
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

    func signedInCredentials() async throws -> Credentials? {
        try await service.credentials(for: "openai") // auto-refreshes when expired
    }

    func signOut() async throws {
        try await service.logout(providerId: "openai")
        credentials = nil
    }
}
```

For an `@Observable` view-model that already wraps `AuthService`, use
`AuthState(service:providerId:)` from `CodingPlanAuth`.

## Calling Codex (plan-bound)

After sign-in, `Credentials.accountId` is non-nil — that's the
`chatgpt-account-id` header the backend uses to bill the user's plan.

### Buffered

```swift
import CodingPlanCodex

let codex = OpenAICodexClient()
let response = try await codex.createTextResponse(
    prompt: "Refactor this Swift function...",
    credentials: credentials
)
print(response.text)
```

### Streaming text deltas

```swift
for try await delta in codex.streamTextResponse(
    prompt: "...",
    credentials: credentials
) {
    print(delta, terminator: "")
}
```

### Streaming text + image events

```swift
for try await part in codex.streamResponse(
    prompt: "Generate a poster of...",
    credentials: credentials,
    tools: [.imageGenerationPNG]
) {
    switch part {
    case .textDelta(let s): print(s, terminator: "")
    case .imageEvent(.started): // show placeholder
    case .imageEvent(.partial(let img)): // swap in low-fi PNG
    case .imageEvent(.completed(let img)): // swap in final PNG
    default: break
    }
}
```

### Usage / rate limits

```swift
let usage = OpenAICodexUsageClient()
let snapshot = try await usage.fetchRateLimits(credentials: credentials)
print(snapshot.rateLimits.primary?.usedPercent ?? 0)
```

### Other plan-bound endpoints (use only when relevant)

- `OpenAICodexEnvironmentsClient` — `wham/environments` and config-requirements file
- `OpenAICodexModelsClient` — `codex/models` (pass a recent CLI semver as `clientVersion`, e.g. `"0.150.0"` — the backend rejects non-SemVer or stale values)
- `OpenAICodexTasksClient` — list / get / create cloud tasks, sibling turns
- `OpenAICodexSafetyClient` — ARC monitor; auth via plan credentials or `CODEX_ARC_MONITOR_TOKEN`
- `OpenAICodexClient.compactResponse(...)` and `summarizeMemories(...)` — Codex agent loop helpers

## Behaviours worth knowing

- **Tokens auto-refresh.** `AuthService.credentials(for:)` returns a refreshed `Credentials` if the access token is past `expiresAt - 60s`. Always call it on the way to a Codex request rather than caching the value.
- **Errors are typed.**
  - `AuthError.tokenExchangeFailed(statusCode:message:)` carries the HTTP status.
  - `CodexError.backendError(statusCode: Int?, message:)` — `statusCode` is nil when the failure was reported as an SSE event over an HTTP 200 stream (`response.failed` / `response.incomplete`).
  - `CodexError.missingAccountId` means the user isn't actually on a plan-bound account; treat as "log them out and ask to sign in again".
- **Custom URL schemes vs. localhost.** `OpenAIAuthProvider(callbackScheme:)` switches the engine to bridge through your scheme so `ASWebAuthenticationSession` can dismiss; without it the provider redirects through a localhost server on port 1455 by default.
- **App Group / extension sharing.** Pass `accessGroup:` to `KeychainTokenStorage` to share credentials with widgets / extensions.
- **Long stalls during image generation.** The streaming request timeout is 5 minutes by default — image events (`.started` / `.generating` / `.keepalive`) fire while bytes are silent.

## Adding a new auth provider (Anthropic, Google, …)

Three files, no changes to `Core/`:

1. `XxxOAuthConfig` — static factory returning an `OAuthConfig` (client id, endpoints, scopes).
2. `XxxTokenResponseParser: OAuth2TokenResponseParser` — decodes the provider's JWT claim shape into `Credentials`.
3. `XxxAuthProvider: AuthProvider` — actor that constructs an `OAuth2PKCEFlow(providerId:config:parser:…)` and forwards `beginLogin()` / `refresh(credentials:)` to it.

Plan-bound API clients for that provider should ship in their own SPM
target / product so adopters who only want auth don't take them along.

## Things to avoid

- Don't read `Credentials.accessToken` directly — always go through `AuthService.credentials(for:)` so refresh happens.
- Don't keep the `LoginSession` around after `complete(with:)` — it's single-shot.
- Don't put the OpenAI client id in your own config — `OpenAIOAuthConfig.default()` already matches the official Codex CLI flow.
- Don't roll your own SSE parsing on top of `streamTextResponse` — use `streamResponse` if you need image events.

## When to fetch the source for verification

Reach for the file via the `llms.txt` path when:
- The user references a type not covered above (`JSONValue`, `CodexArcResult`, `CodexTaskListItem`, etc.).
- They want to write a new provider and need the protocol shapes.
- They get a typed error you don't recognise.

The repo follows Hexagonal / Ports-and-Adapters: domain protocols in
`Sources/CodingPlanAuth/Core/`, infrastructure adapters in `Infrastructure/`,
provider strategies in `Providers/`. The `llms.txt` index links each file
directly.
