// OpenAICodexSafetyClient.swift
// CodingPlanCodex
//
// `POST /codex/safety/arc` — Codex's "ARC monitor" endpoint that scores
// a proposed action against safety policies and returns whether to allow,
// steer the model, or ask the user. Auth is dual-mode: either the user's
// plan credentials, or a separate Bearer token (used by the official CLI
// when CODEX_ARC_MONITOR_TOKEN is set).
//
// Request and response shapes are deeply nested and Codex-internal; we
// expose them as JSONValue passthrough.

import CodingPlanAuth
import Foundation

/// The high-level outcome reported by the ARC monitor.
public enum CodexArcOutcome: String, Sendable, Codable, Equatable {
    case ok = "ok"
    case steerModel = "steer-model"
    case askUser = "ask-user"
}

/// Risk level the monitor assigned to the action.
public enum CodexArcRiskLevel: String, Sendable, Codable, Equatable {
    case low
    case medium
    case high
    case critical
}

/// One piece of evidence the monitor cited for its outcome.
public struct CodexArcEvidence: Sendable, Equatable, Codable {
    public let message: String
    public let why: String
    public init(message: String, why: String) {
        self.message = message
        self.why = why
    }
}

/// Decoded ARC monitor response.
public struct CodexArcResult: Sendable, Equatable, Codable {
    public let outcome: CodexArcOutcome
    public let shortReason: String
    public let rationale: String
    public let riskScore: Int
    public let riskLevel: CodexArcRiskLevel
    public let evidence: [CodexArcEvidence]

    enum CodingKeys: String, CodingKey {
        case outcome
        case shortReason = "short_reason"
        case rationale
        case riskScore = "risk_score"
        case riskLevel = "risk_level"
        case evidence
    }

    public init(
        outcome: CodexArcOutcome,
        shortReason: String,
        rationale: String,
        riskScore: Int,
        riskLevel: CodexArcRiskLevel,
        evidence: [CodexArcEvidence]
    ) {
        self.outcome = outcome
        self.shortReason = shortReason
        self.rationale = rationale
        self.riskScore = riskScore
        self.riskLevel = riskLevel
        self.evidence = evidence
    }
}

/// How `OpenAICodexSafetyClient` authenticates.
public enum CodexArcAuth: Sendable {
    /// Use the signed-in user's plan credentials.
    case planCredentials(Credentials)
    /// Use a static Bearer token (CODEX_ARC_MONITOR_TOKEN style).
    case monitorToken(String)
}

/// Client for the ARC safety-monitor endpoint.
public struct OpenAICodexSafetyClient: Sendable {
    private let httpClient: any HTTPClient
    private let baseURL: URL
    private let originator: String

    public init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        baseURL: URL = OpenAIBackend.defaultBaseURL,
        originator: String = OpenAIBackend.defaultOriginator
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.originator = originator
    }

    /// Score a proposed action against the ARC safety monitor.
    ///
    /// - Parameters:
    ///   - body: The full request body (`metadata`, `messages` / `input`,
    ///     `policies`, `action`). Pass as ``JSONValue`` since the upstream
    ///     shape is deep and provider-internal.
    ///   - auth: Either plan credentials or a dedicated monitor token.
    public func evaluate(
        body: JSONValue,
        auth: CodexArcAuth
    ) async throws -> CodexArcResult {
        let url = baseURL.appendingPathComponent("codex/safety/arc")
        let bodyData = try JSONEncoder().encode(body)

        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "originator": originator,
        ]
        switch auth {
        case .planCredentials(let credentials):
            guard let accountId = credentials.accountId, !accountId.isEmpty else {
                throw CodexError.missingAccountId
            }
            headers["Authorization"] = "Bearer \(credentials.accessToken)"
            headers["ChatGPT-Account-Id"] = accountId
        case .monitorToken(let token):
            headers["Authorization"] = "Bearer \(token)"
        }

        let response = try await httpClient.send(HTTPRequest(
            url: url,
            method: .post,
            headers: headers,
            body: bodyData
        ))

        guard response.isSuccess else {
            let message = String(data: response.body, encoding: .utf8) ?? "Unknown error"
            throw CodexError.backendError(statusCode: response.statusCode, message: message)
        }

        return try JSONDecoder().decode(CodexArcResult.self, from: response.body)
    }
}
