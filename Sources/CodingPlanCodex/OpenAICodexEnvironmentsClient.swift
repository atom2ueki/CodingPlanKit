// OpenAICodexEnvironmentsClient.swift
// CodingPlanCodex
//
// `/wham/environments`, `/wham/environments/by-repo/...`, and
// `/wham/config/requirements`. Mirrors the official Codex CLI's
// cloud-tasks environment selection + managed config endpoints.

import CodingPlanAuth
import Foundation

/// One execution environment a Codex cloud task can run in.
public struct CodexEnvironment: Sendable, Equatable {
    public let id: String
    public let label: String?
    public let isPinned: Bool?
    public let taskCount: Int?

    public init(id: String, label: String? = nil, isPinned: Bool? = nil, taskCount: Int? = nil) {
        self.id = id
        self.label = label
        self.isPinned = isPinned
        self.taskCount = taskCount
    }
}

/// The "managed requirements" file the backend keeps for a workspace.
public struct CodexConfigRequirements: Sendable, Equatable {
    public let contents: String?
    public let sha256: String?
    public let updatedAt: String?
    public let updatedByUserId: String?

    public init(
        contents: String? = nil,
        sha256: String? = nil,
        updatedAt: String? = nil,
        updatedByUserId: String? = nil
    ) {
        self.contents = contents
        self.sha256 = sha256
        self.updatedAt = updatedAt
        self.updatedByUserId = updatedByUserId
    }
}

/// Client for the plan-bound environments + config-requirements endpoints.
public struct OpenAICodexEnvironmentsClient: Sendable {
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

    /// `GET /wham/environments` — list all environments visible to the
    /// signed-in plan, regardless of repo.
    public func listEnvironments(credentials: Credentials) async throws -> [CodexEnvironment] {
        try await fetchEnvironments(
            url: baseURL.appendingPathComponent("wham/environments"),
            credentials: credentials
        )
    }

    /// `GET /wham/environments/by-repo/{provider}/{owner}/{repo}` —
    /// environments scoped to one source-control repo (GitHub today).
    ///
    /// - Parameters:
    ///   - provider: SCM provider id, e.g. `"github"`.
    ///   - owner: Repo owner / organization.
    ///   - repo: Repo name.
    ///   - credentials: Plan credentials.
    public func listEnvironments(
        provider: String,
        owner: String,
        repo: String,
        credentials: Credentials
    ) async throws -> [CodexEnvironment] {
        let path = "wham/environments/by-repo/\(provider)/\(owner)/\(repo)"
        return try await fetchEnvironments(
            url: baseURL.appendingPathComponent(path),
            credentials: credentials
        )
    }

    /// `GET /wham/config/requirements` — the workspace-managed
    /// `requirements` file (Codex's cloud-task setup script).
    public func fetchConfigRequirements(
        credentials: Credentials
    ) async throws -> CodexConfigRequirements {
        let accountId = try requireAccountId(credentials)
        let url = baseURL.appendingPathComponent("wham/config/requirements")

        let response = try await httpClient.send(HTTPRequest(
            url: url,
            method: .get,
            headers: standardHeaders(credentials: credentials, accountId: accountId)
        ))
        try ensureSuccess(response)

        struct Wire: Decodable {
            let contents: String?
            let sha256: String?
            let updated_at: String?
            let updated_by_user_id: String?
        }
        let wire = try JSONDecoder().decode(Wire.self, from: response.body)
        return CodexConfigRequirements(
            contents: wire.contents,
            sha256: wire.sha256,
            updatedAt: wire.updated_at,
            updatedByUserId: wire.updated_by_user_id
        )
    }

    // MARK: - Helpers

    private func fetchEnvironments(url: URL, credentials: Credentials) async throws -> [CodexEnvironment] {
        let accountId = try requireAccountId(credentials)
        let response = try await httpClient.send(HTTPRequest(
            url: url,
            method: .get,
            headers: standardHeaders(credentials: credentials, accountId: accountId)
        ))
        try ensureSuccess(response)

        struct Wire: Decodable {
            let id: String
            let label: String?
            let is_pinned: Bool?
            let task_count: Int?
        }
        let wire = try JSONDecoder().decode([Wire].self, from: response.body)
        return wire.map {
            CodexEnvironment(id: $0.id, label: $0.label, isPinned: $0.is_pinned, taskCount: $0.task_count)
        }
    }

    private func requireAccountId(_ credentials: Credentials) throws -> String {
        guard let accountId = credentials.accountId, !accountId.isEmpty else {
            throw CodexError.missingAccountId
        }
        return accountId
    }

    private func standardHeaders(credentials: Credentials, accountId: String) -> [String: String] {
        [
            "Authorization": "Bearer \(credentials.accessToken)",
            "ChatGPT-Account-Id": accountId,
            "originator": originator,
            "Accept": "application/json",
        ]
    }

    private func ensureSuccess(_ response: HTTPResponse) throws {
        guard response.isSuccess else {
            let message = String(data: response.body, encoding: .utf8) ?? "Unknown error"
            throw CodexError.backendError(statusCode: response.statusCode, message: message)
        }
    }
}
