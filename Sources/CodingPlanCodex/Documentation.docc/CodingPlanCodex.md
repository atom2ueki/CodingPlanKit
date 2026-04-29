@Metadata {
    @DisplayName("CodingPlanCodex")
}

# ``CodingPlanCodex``

Plan-bound API clients for the OpenAI ChatGPT / Codex backend.

## Overview

This product sits on top of `CodingPlanAuth` and consumes its
`Credentials` to charge requests against the signed-in user's plan
instead of an API key.

```swift
import CodingPlanAuth
import CodingPlanCodex

let codex = OpenAICodexClient()
let response = try await codex.createTextResponse(
    prompt: "Refactor this Swift function...",
    credentials: credentials
)

// Or stream deltas as they arrive:
for try await delta in codex.streamTextResponse(prompt: "...", credentials: credentials) {
    print(delta, terminator: "")
}
```

For quota / rate-limit visibility:

```swift
let usage = OpenAICodexUsageClient()
let snapshot = try await usage.fetchRateLimits(credentials: credentials)
print(snapshot.rateLimits.primary?.remainingPercent ?? 100)
```

## Topics

### Codex API

- ``OpenAICodexClient``
- ``OpenAICodexResponse``

### Usage / rate limits

- ``OpenAICodexUsageClient``
- ``CodexRateLimitsResponse``
- ``CodexRateLimitSnapshot``
- ``CodexRateLimitWindow``
- ``CodexCreditsSnapshot``
- ``CodexCreditNudgeType``

### Models

- ``OpenAICodexModelsClient``
- ``CodexModelInfo``
- ``CodexModelVisibility``

### Cloud tasks

- ``OpenAICodexTasksClient``
- ``CodexTaskListItem``
- ``CodexTaskList``
- ``CodexTaskDetails``
- ``CodexSiblingTurns``

### Environments / managed config

- ``OpenAICodexEnvironmentsClient``
- ``CodexEnvironment``
- ``CodexConfigRequirements``

### Safety monitor

- ``OpenAICodexSafetyClient``
- ``CodexArcAuth``
- ``CodexArcResult``
- ``CodexArcOutcome``
- ``CodexArcRiskLevel``
- ``CodexArcEvidence``

### Generic JSON

- ``JSONValue``

### Configuration

- ``OpenAIBackend``

### Errors

- ``CodexError``
