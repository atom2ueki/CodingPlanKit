// OpenAICodexTasksClient.swift
// CodingPlanCodex
//
// Plan-bound cloud-task management endpoints (`/wham/tasks/...`).
// Mirrors the official Codex CLI's `backend-client` task surface.

import CodingPlanAuth
import Foundation

/// One row in the cloud-tasks list. Mirrors the upstream
/// `TaskListItem` openapi model with the most useful fields surfaced.
public struct CodexTaskListItem: Sendable, Equatable {
    public let id: String
    public let title: String
    public let archived: Bool
    public let hasUnreadTurn: Bool
    public let hasGeneratedTitle: Bool?
    public let createdAt: Date?
    public let updatedAt: Date?
    /// Backend-defined display block (status text, color, etc.). Surfaced
    /// as ``JSONValue`` because the upstream shape evolves freely.
    public let taskStatusDisplay: JSONValue?
    /// Pull requests associated with this task, in their raw JSON shape.
    public let pullRequests: [JSONValue]

    public init(
        id: String,
        title: String,
        archived: Bool,
        hasUnreadTurn: Bool,
        hasGeneratedTitle: Bool? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        taskStatusDisplay: JSONValue? = nil,
        pullRequests: [JSONValue] = []
    ) {
        self.id = id
        self.title = title
        self.archived = archived
        self.hasUnreadTurn = hasUnreadTurn
        self.hasGeneratedTitle = hasGeneratedTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.taskStatusDisplay = taskStatusDisplay
        self.pullRequests = pullRequests
    }
}

/// Paged result of ``OpenAICodexTasksClient/listTasks(limit:filter:environmentId:cursor:credentials:)``.
public struct CodexTaskList: Sendable, Equatable {
    public let items: [CodexTaskListItem]
    /// Opaque pagination cursor. Pass back to the next call to fetch the
    /// following page; `nil` when no more pages.
    public let cursor: String?

    public init(items: [CodexTaskListItem], cursor: String? = nil) {
        self.items = items
        self.cursor = cursor
    }
}

/// The full task-details payload, decoded as ``JSONValue`` plus the raw
/// bytes for callers that want to plug it into their own `Decodable`.
public struct CodexTaskDetails: Sendable, Equatable {
    public let json: JSONValue
    public let rawJSON: Data

    public init(json: JSONValue, rawJSON: Data) {
        self.json = json
        self.rawJSON = rawJSON
    }
}

/// Sibling-turn payload as returned by
/// `/wham/tasks/{id}/turns/{turn_id}/sibling_turns`.
public struct CodexSiblingTurns: Sendable, Equatable {
    public let siblingTurns: [JSONValue]

    public init(siblingTurns: [JSONValue]) {
        self.siblingTurns = siblingTurns
    }
}

/// Client for the plan-bound cloud-task management endpoints.
public struct OpenAICodexTasksClient: Sendable {
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

    /// `GET /wham/tasks/list` — list cloud tasks, paginated.
    ///
    /// - Parameters:
    ///   - limit: Maximum number of items to return on this page.
    ///   - filter: Backend-defined filter token (e.g. `"open"`, `"archived"`).
    ///   - environmentId: When set, only tasks belonging to this environment.
    ///   - cursor: Pagination cursor returned by a previous call.
    ///   - credentials: Plan credentials.
    public func listTasks(
        limit: Int? = nil,
        filter: String? = nil,
        environmentId: String? = nil,
        cursor: String? = nil,
        credentials: Credentials
    ) async throws -> CodexTaskList {
        let accountId = try requireAccountId(credentials)
        var components = URLComponents(
            url: baseURL.appendingPathComponent("wham/tasks/list"),
            resolvingAgainstBaseURL: false
        )
        var query: [URLQueryItem] = []
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let filter { query.append(URLQueryItem(name: "task_filter", value: filter)) }
        if let environmentId { query.append(URLQueryItem(name: "environment_id", value: environmentId)) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw CodexError.invalidResponse }

        let response = try await httpClient.send(HTTPRequest(
            url: url,
            method: .get,
            headers: standardHeaders(credentials: credentials, accountId: accountId)
        ))

        try ensureSuccess(response)
        return try Self.parseTaskList(response.body)
    }

    /// `GET /wham/tasks/{id}` — full details for one task.
    public func getTask(id: String, credentials: Credentials) async throws -> CodexTaskDetails {
        let accountId = try requireAccountId(credentials)
        let url = baseURL.appendingPathComponent("wham/tasks/\(id)")

        let response = try await httpClient.send(HTTPRequest(
            url: url,
            method: .get,
            headers: standardHeaders(credentials: credentials, accountId: accountId)
        ))

        try ensureSuccess(response)
        let json = try JSONDecoder().decode(JSONValue.self, from: response.body)
        return CodexTaskDetails(json: json, rawJSON: response.body)
    }

    /// `GET /wham/tasks/{id}/turns/{turn_id}/sibling_turns` — fetch the
    /// list of parallel attempts for a task turn.
    public func getSiblingTurns(
        taskId: String,
        turnId: String,
        credentials: Credentials
    ) async throws -> CodexSiblingTurns {
        let accountId = try requireAccountId(credentials)
        let url = baseURL.appendingPathComponent(
            "wham/tasks/\(taskId)/turns/\(turnId)/sibling_turns"
        )

        let response = try await httpClient.send(HTTPRequest(
            url: url,
            method: .get,
            headers: standardHeaders(credentials: credentials, accountId: accountId)
        ))

        try ensureSuccess(response)
        guard case .object(let outer) = try JSONDecoder().decode(JSONValue.self, from: response.body),
              case .array(let arr) = outer["sibling_turns"] ?? .array([]) else {
            return CodexSiblingTurns(siblingTurns: [])
        }
        return CodexSiblingTurns(siblingTurns: arr)
    }

    /// `POST /wham/tasks` — create a new cloud task. The body shape is
    /// rich and evolving; pass arbitrary JSON. Returns the new task id.
    public func createTask(body: JSONValue, credentials: Credentials) async throws -> String {
        let accountId = try requireAccountId(credentials)
        let url = baseURL.appendingPathComponent("wham/tasks")
        let bodyData = try JSONEncoder().encode(body)

        var headers = standardHeaders(credentials: credentials, accountId: accountId)
        headers["Content-Type"] = "application/json"

        let response = try await httpClient.send(HTTPRequest(
            url: url,
            method: .post,
            headers: headers,
            body: bodyData
        ))

        try ensureSuccess(response)
        return try Self.extractTaskId(response.body)
    }

    // MARK: - Helpers

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

    static func parseTaskList(_ data: Data) throws -> CodexTaskList {
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let outer) = value,
              case .array(let arr) = outer["items"] ?? .array([]) else {
            throw CodexError.invalidResponse
        }
        let cursor: String? = {
            if case .string(let s) = outer["cursor"] ?? .null { return s }
            return nil
        }()
        let items: [CodexTaskListItem] = arr.compactMap { taskListItem(from: $0) }
        return CodexTaskList(items: items, cursor: cursor)
    }

    private static func taskListItem(from value: JSONValue) -> CodexTaskListItem? {
        guard case .object(let dict) = value,
              case .string(let id) = dict["id"] ?? .null,
              case .string(let title) = dict["title"] ?? .null else {
            return nil
        }
        let archived: Bool = {
            if case .bool(let b) = dict["archived"] ?? .null { return b }
            return false
        }()
        let hasUnread: Bool = {
            if case .bool(let b) = dict["has_unread_turn"] ?? .null { return b }
            return false
        }()
        let hasGenerated: Bool? = {
            if case .bool(let b) = dict["has_generated_title"] ?? .null { return b }
            return nil
        }()
        let created = epochDate(from: dict["created_at"])
        let updated = epochDate(from: dict["updated_at"])
        let prs: [JSONValue] = {
            if case .array(let arr) = dict["pull_requests"] ?? .null { return arr }
            return []
        }()
        return CodexTaskListItem(
            id: id,
            title: title,
            archived: archived,
            hasUnreadTurn: hasUnread,
            hasGeneratedTitle: hasGenerated,
            createdAt: created,
            updatedAt: updated,
            taskStatusDisplay: dict["task_status_display"],
            pullRequests: prs
        )
    }

    private static func epochDate(from value: JSONValue?) -> Date? {
        guard let value else { return nil }
        switch value {
        case .double(let d): return Date(timeIntervalSince1970: d)
        case .integer(let i): return Date(timeIntervalSince1970: TimeInterval(i))
        default: return nil
        }
    }

    static func extractTaskId(_ data: Data) throws -> String {
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        if case .object(let outer) = value {
            if case .object(let task) = outer["task"] ?? .null,
               case .string(let id) = task["id"] ?? .null {
                return id
            }
            if case .string(let id) = outer["id"] ?? .null {
                return id
            }
        }
        throw CodexError.invalidResponse
    }
}
