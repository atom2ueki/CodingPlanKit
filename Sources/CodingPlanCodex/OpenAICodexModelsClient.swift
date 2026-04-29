// OpenAICodexModelsClient.swift
// CodingPlanCodex
//
// `GET /codex/models?client_version=…` — fetch the list of Codex models
// available to the signed-in plan, plus an optional ETag for caching.

import CodingPlanAuth
import Foundation

/// Visibility of a model in the Codex picker UI. Other values may appear in
/// future Codex releases; unknown raw values round-trip via `.other`.
public enum CodexModelVisibility: Sendable, Equatable, Hashable {
    case list
    case hidden
    case experimental
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "list": self = .list
        case "hidden": self = .hidden
        case "experimental": self = .experimental
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .list: "list"
        case .hidden: "hidden"
        case .experimental: "experimental"
        case .other(let v): v
        }
    }
}

/// One Codex model entry as returned by `/codex/models`.
///
/// Only the fields most useful to app callers are surfaced as named
/// properties. The full upstream JSON shape carries many more flags
/// (verbosity support, tool support, truncation policy, etc.); they are
/// decoded into ``rawJSON`` for callers that need them.
public struct CodexModelInfo: Sendable, Equatable {
    /// Stable model id used in chat requests (e.g. `"gpt-5.5"`).
    public let slug: String
    /// Display name suitable for a model picker.
    public let displayName: String
    /// Human-readable description of the model's strengths.
    public let description: String?
    /// Maximum context window in tokens, when reported.
    public let contextWindow: Int?
    /// `true` when the model is callable via the Codex `/responses` endpoint.
    public let supportedInApi: Bool
    /// Sort order in the upstream picker.
    public let priority: Int?
    /// Visibility classification.
    public let visibility: CodexModelVisibility?
    /// Default reasoning effort (`"low"`, `"medium"`, `"high"`, …) when set.
    public let defaultReasoningLevel: String?

    /// The full decoded JSON object so callers can reach fields not
    /// surfaced as named properties.
    public let rawJSON: Data?

    public init(
        slug: String,
        displayName: String,
        description: String? = nil,
        contextWindow: Int? = nil,
        supportedInApi: Bool = true,
        priority: Int? = nil,
        visibility: CodexModelVisibility? = nil,
        defaultReasoningLevel: String? = nil,
        rawJSON: Data? = nil
    ) {
        self.slug = slug
        self.displayName = displayName
        self.description = description
        self.contextWindow = contextWindow
        self.supportedInApi = supportedInApi
        self.priority = priority
        self.visibility = visibility
        self.defaultReasoningLevel = defaultReasoningLevel
        self.rawJSON = rawJSON
    }
}

/// Client for the `/codex/models` endpoint.
public struct OpenAICodexModelsClient: Sendable {
    private let httpClient: any HTTPClient
    private let baseURL: URL
    private let originator: String

    /// Create a new models client.
    public init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        baseURL: URL = OpenAIBackend.defaultBaseURL,
        originator: String = OpenAIBackend.defaultOriginator
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.originator = originator
    }

    /// List the Codex models available to the signed-in plan.
    ///
    /// - Parameters:
    ///   - clientVersion: Identifies the client to the backend. The
    ///     official Codex CLI passes its CLI version (e.g. `"0.99.0"`).
    ///   - credentials: Plan credentials from ``AuthService/credentials(for:)``.
    /// - Returns: A tuple of `(models, etag)`. The ETag, when present,
    ///   can be used by the caller for conditional revalidation later.
    public func listModels(
        clientVersion: String,
        credentials: Credentials
    ) async throws -> (models: [CodexModelInfo], etag: String?) {
        guard let accountId = credentials.accountId, !accountId.isEmpty else {
            throw CodexError.missingAccountId
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("codex/models"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "client_version", value: clientVersion)]
        guard let url = components?.url else {
            throw CodexError.invalidResponse
        }

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

        let etag = response.headers.first(where: { $0.key.caseInsensitiveCompare("etag") == .orderedSame })?.value
        let models = try Self.parse(response.body)
        return (models, etag)
    }

    static func parse(_ data: Data) throws -> [CodexModelInfo] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsJSON = object["models"] as? [[String: Any]] else {
            throw CodexError.invalidResponse
        }

        return try modelsJSON.map { dict in
            guard let slug = dict["slug"] as? String,
                  let displayName = dict["display_name"] as? String else {
                throw CodexError.invalidResponse
            }
            let raw = try? JSONSerialization.data(withJSONObject: dict)
            return CodexModelInfo(
                slug: slug,
                displayName: displayName,
                description: dict["description"] as? String,
                contextWindow: dict["context_window"] as? Int,
                supportedInApi: (dict["supported_in_api"] as? Bool) ?? true,
                priority: dict["priority"] as? Int,
                visibility: (dict["visibility"] as? String).map(CodexModelVisibility.init(rawValue:)),
                defaultReasoningLevel: dict["default_reasoning_level"] as? String,
                rawJSON: raw
            )
        }
    }
}
