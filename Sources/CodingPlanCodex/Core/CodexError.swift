// CodexError.swift
// CodingPlanCodex

import Foundation

/// Errors thrown by the plan-bound Codex / usage API clients.
public enum CodexError: Error, Sendable, Equatable {
    /// The credentials don't carry an `accountId` — the user has not signed in
    /// to a plan-bound account, or the JWT didn't contain the expected claim.
    case missingAccountId

    /// The backend returned a non-2xx status, or a streaming SSE event
    /// reported failure mid-stream. `statusCode` is `nil` when the failure
    /// was carried by a streaming event rather than the HTTP envelope.
    /// `message` is the best-effort description extracted from the body.
    case backendError(statusCode: Int?, message: String)

    /// The response body was missing or shaped in an unexpected way.
    case invalidResponse
}

extension CodexError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAccountId:
            "No plan-bound account id is associated with these credentials."
        case .backendError(let status, let message):
            if let status {
                "Codex backend returned \(status): \(message)"
            } else {
                "Codex backend returned a failure event: \(message)"
            }
        case .invalidResponse:
            "The Codex backend returned an unexpected response."
        }
    }
}
