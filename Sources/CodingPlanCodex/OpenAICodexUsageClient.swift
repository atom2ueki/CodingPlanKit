// OpenAICodexUsageClient.swift
// CodingPlanCodex

import CodingPlanAuthKit
import Foundation

/// Aggregated quota snapshot returned by ``OpenAICodexUsageClient``.
public struct CodexRateLimitsResponse: Sendable, Equatable {
    /// The primary "codex" limit, surfaced for convenience.
    public let rateLimits: CodexRateLimitSnapshot

    /// All known limits, keyed by their backend id (`"codex"`, etc.).
    public let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]

    public init(
        rateLimits: CodexRateLimitSnapshot,
        rateLimitsByLimitId: [String: CodexRateLimitSnapshot]
    ) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
    }
}

/// One rate-limit "bucket" with its usage windows and credit balance.
public struct CodexRateLimitSnapshot: Sendable, Equatable {
    /// Backend identifier for this limit (e.g. `"codex"`).
    public let limitId: String?
    /// Human-readable limit name as returned by the backend.
    public let limitName: String?
    /// Short rolling window (typically 5 hours).
    public let primary: CodexRateLimitWindow?
    /// Long rolling window (typically weekly).
    public let secondary: CodexRateLimitWindow?
    /// Pay-as-you-go credit state for this limit, when applicable.
    public let credits: CodexCreditsSnapshot?
    /// Plan tier label (e.g. `"plus"`, `"team"`).
    public let planType: String?
    /// If the user has hit the limit, the type of throttle the backend applied.
    public let rateLimitReachedType: String?

    public init(
        limitId: String?,
        limitName: String?,
        primary: CodexRateLimitWindow?,
        secondary: CodexRateLimitWindow?,
        credits: CodexCreditsSnapshot?,
        planType: String?,
        rateLimitReachedType: String?
    ) {
        self.limitId = limitId
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.planType = planType
        self.rateLimitReachedType = rateLimitReachedType
    }
}

/// One rolling-window slice of a Codex rate limit.
public struct CodexRateLimitWindow: Sendable, Equatable {
    /// Percent of the window already consumed (0-100).
    public let usedPercent: Double
    /// Length of the window in minutes, when known.
    public let windowDurationMinutes: Int?
    /// Wall-clock instant when the window rolls over.
    public let resetsAt: Date?

    public init(
        usedPercent: Double,
        windowDurationMinutes: Int?,
        resetsAt: Date?
    ) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    /// Percent of the window remaining (0-100), clamped.
    public var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }
}

/// Pay-as-you-go credit balance reported alongside rate limits.
public struct CodexCreditsSnapshot: Sendable, Equatable {
    /// `true` when any pay-as-you-go credits are present.
    public let hasCredits: Bool
    /// `true` when the plan grants unlimited usage.
    public let unlimited: Bool
    /// Backend-formatted credit balance string, when present.
    public let balance: String?

    public init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}

/// Client for the plan-bound usage / rate-limits endpoint.
public struct OpenAICodexUsageClient: Sendable {
    private let httpClient: any HTTPClient
    private let baseURL: URL
    private let originator: String

    /// Create a new usage client.
    public init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        baseURL: URL = OpenAIBackend.defaultBaseURL,
        originator: String = OpenAIBackend.defaultOriginator
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.originator = originator
    }

    /// Fetch the current rate-limit and credit snapshot for the signed-in user.
    public func fetchRateLimits(credentials: Credentials) async throws -> CodexRateLimitsResponse {
        guard let accountId = credentials.accountId, !accountId.isEmpty else {
            throw CodexError.missingAccountId
        }

        let url = baseURL.appendingPathComponent("wham/usage")
        let response = try await httpClient.send(HTTPRequest(
            url: url,
            method: .get,
            headers: [
                "Authorization": "Bearer \(credentials.accessToken)",
                "ChatGPT-Account-Id": accountId,
                "originator": originator,
                "Accept": "application/json",
            ]
        ))

        guard response.isSuccess else {
            let message = String(data: response.body, encoding: .utf8) ?? "Unknown error"
            throw CodexError.backendError(statusCode: response.statusCode, message: message)
        }

        let payload = try JSONDecoder().decode(RateLimitStatusPayload.self, from: response.body)
        let snapshots = Self.rateLimitSnapshots(from: payload)
        guard let selected = snapshots.first(where: { $0.limitId == "codex" }) ?? snapshots.first else {
            throw CodexError.invalidResponse
        }

        var byLimitId: [String: CodexRateLimitSnapshot] = [:]
        for snapshot in snapshots {
            byLimitId[snapshot.limitId ?? "codex"] = snapshot
        }
        return CodexRateLimitsResponse(rateLimits: selected, rateLimitsByLimitId: byLimitId)
    }

    private static func rateLimitSnapshots(from payload: RateLimitStatusPayload) -> [CodexRateLimitSnapshot] {
        var snapshots = [
            makeRateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                rateLimit: payload.rateLimit,
                credits: payload.credits,
                planType: payload.planType,
                rateLimitReachedType: payload.rateLimitReachedType?.type
            ),
        ]

        snapshots.append(contentsOf: payload.additionalRateLimits.map { details in
            makeRateLimitSnapshot(
                limitId: details.meteredFeature,
                limitName: details.limitName,
                rateLimit: details.rateLimit,
                credits: nil,
                planType: payload.planType,
                rateLimitReachedType: nil
            )
        })

        return snapshots
    }

    private static func makeRateLimitSnapshot(
        limitId: String?,
        limitName: String?,
        rateLimit: RateLimitStatusDetails?,
        credits: CreditStatusDetails?,
        planType: String?,
        rateLimitReachedType: String?
    ) -> CodexRateLimitSnapshot {
        CodexRateLimitSnapshot(
            limitId: limitId,
            limitName: limitName,
            primary: rateLimit?.primaryWindow.map(rateLimitWindow),
            secondary: rateLimit?.secondaryWindow.map(rateLimitWindow),
            credits: credits.map {
                CodexCreditsSnapshot(
                    hasCredits: $0.hasCredits,
                    unlimited: $0.unlimited,
                    balance: $0.balance
                )
            },
            planType: planType,
            rateLimitReachedType: rateLimitReachedType
        )
    }

    private static func rateLimitWindow(_ snapshot: RateLimitWindowSnapshot) -> CodexRateLimitWindow {
        CodexRateLimitWindow(
            usedPercent: Double(snapshot.usedPercent),
            windowDurationMinutes: windowDurationMinutes(fromSeconds: snapshot.limitWindowSeconds),
            resetsAt: Date(timeIntervalSince1970: TimeInterval(snapshot.resetAt))
        )
    }

    private static func windowDurationMinutes(fromSeconds seconds: Int) -> Int? {
        guard seconds > 0 else { return nil }
        return (seconds + 59) / 60
    }
}

private struct RateLimitStatusPayload: Decodable {
    let planType: String?
    let rateLimit: RateLimitStatusDetails?
    let credits: CreditStatusDetails?
    let additionalRateLimits: [AdditionalRateLimitDetails]
    let rateLimitReachedType: RateLimitReachedType?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
        case additionalRateLimits = "additional_rate_limits"
        case rateLimitReachedType = "rate_limit_reached_type"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        rateLimit = try container.decodeIfPresent(RateLimitStatusDetails.self, forKey: .rateLimit)
        credits = try container.decodeIfPresent(CreditStatusDetails.self, forKey: .credits)
        additionalRateLimits = try container.decodeIfPresent([AdditionalRateLimitDetails].self, forKey: .additionalRateLimits) ?? []
        rateLimitReachedType = try container.decodeIfPresent(RateLimitReachedType.self, forKey: .rateLimitReachedType)
    }
}

private struct RateLimitStatusDetails: Decodable {
    let primaryWindow: RateLimitWindowSnapshot?
    let secondaryWindow: RateLimitWindowSnapshot?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct RateLimitWindowSnapshot: Decodable {
    let usedPercent: Int
    let limitWindowSeconds: Int
    let resetAt: Int

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }
}

private struct CreditStatusDetails: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}

private struct AdditionalRateLimitDetails: Decodable {
    let limitName: String
    let meteredFeature: String
    let rateLimit: RateLimitStatusDetails?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case meteredFeature = "metered_feature"
        case rateLimit = "rate_limit"
    }
}

private struct RateLimitReachedType: Decodable {
    let type: String
}
