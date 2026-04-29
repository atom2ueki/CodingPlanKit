// OpenAICodexClient.swift
// CodingPlanCodex

import CodingPlanAuth
import Foundation

/// The non-streaming result of a Codex text-response call.
public struct OpenAICodexResponse: Sendable, Equatable {
    /// The model's full text output.
    public let text: String

    /// The response id reported by the backend, if any.
    public let responseId: String?

    public init(text: String, responseId: String? = nil) {
        self.text = text
        self.responseId = responseId
    }
}

/// Client for the plan-bound Codex `responses` endpoint.
///
/// Uses the credentials returned by ``OpenAIAuthProvider`` to charge the
/// signed-in user's plan rather than an API key.
public struct OpenAICodexClient: Sendable {
    private let httpClient: any HTTPClient
    private let urlSession: URLSession
    private let baseURL: URL
    private let originator: String

    /// Create a new client.
    /// - Parameters:
    ///   - httpClient: Buffered HTTP transport (used by ``createTextResponse(prompt:instructions:model:credentials:)``).
    ///     Defaults to ``URLSessionHTTPClient``.
    ///   - urlSession: `URLSession` used by ``streamTextResponse(prompt:instructions:model:credentials:)``
    ///     for `URLSession.bytes(for:)`. Defaults to `.shared`.
    ///   - baseURL: Backend base URL. Defaults to ``OpenAIBackend/defaultBaseURL``.
    ///   - originator: Originator header. Defaults to ``OpenAIBackend/defaultOriginator``.
    public init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        urlSession: URLSession = .shared,
        baseURL: URL = OpenAIBackend.defaultBaseURL,
        originator: String = OpenAIBackend.defaultOriginator
    ) {
        self.httpClient = httpClient
        self.urlSession = urlSession
        self.baseURL = baseURL
        self.originator = originator
    }

    /// Send a single prompt and return the model's full reply.
    ///
    /// The backend streams SSE deltas; this method collects them and returns
    /// the concatenated text. For streaming UIs, wrap this client in your own
    /// `AsyncSequence` (see roadmap).
    ///
    /// - Parameters:
    ///   - prompt: The user message.
    ///   - instructions: System instructions; defaults to a Codex preset.
    ///   - model: Codex model id; defaults to `"gpt-5.5"`.
    ///   - credentials: The user's plan credentials, normally obtained via ``AuthService/credentials(for:)``.
    public func createTextResponse(
        prompt: String,
        instructions: String = "You are Codex, an AI coding assistant. Follow the user's request and respond concisely.",
        model: String = "gpt-5.5",
        credentials: Credentials
    ) async throws -> OpenAICodexResponse {
        guard let accountId = credentials.accountId, !accountId.isEmpty else {
            throw CodexError.missingAccountId
        }

        let url = baseURL.appendingPathComponent("codex/responses")
        let requestBody: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "tools": [],
            "tool_choice": "auto",
            "parallel_tool_calls": false,
            "store": false,
            "stream": true,
            "include": [],
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": prompt,
                        ],
                    ],
                ],
            ],
        ]
        let body = try JSONSerialization.data(withJSONObject: requestBody)
        let headers = [
            "Authorization": "Bearer \(credentials.accessToken)",
            "chatgpt-account-id": accountId,
            "OpenAI-Beta": "responses=experimental",
            "originator": originator,
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        ]

        let response = try await httpClient.send(HTTPRequest(
            url: url,
            method: .post,
            headers: headers,
            body: body
        ))

        guard response.isSuccess else {
            let message = Self.backendErrorMessage(from: response.body)
            throw CodexError.backendError(statusCode: response.statusCode, message: message)
        }

        return try Self.parseResponse(from: response.body)
    }

    /// `POST /codex/responses/compact` — compress the conversation history
    /// into a smaller set of items that still preserves intent and context.
    ///
    /// Used by the official Codex agent loop when a turn would exceed the
    /// model's context window. Returns the compressed `output` array as
    /// ``JSONValue`` since each item carries a deep, provider-internal shape.
    public func compactResponse(
        body: JSONValue,
        credentials: Credentials
    ) async throws -> [JSONValue] {
        guard let accountId = credentials.accountId, !accountId.isEmpty else {
            throw CodexError.missingAccountId
        }
        let url = baseURL.appendingPathComponent("codex/responses/compact")
        let bodyData = try JSONEncoder().encode(body)

        let response = try await httpClient.send(HTTPRequest(
            url: url,
            method: .post,
            headers: [
                "Authorization": "Bearer \(credentials.accessToken)",
                "chatgpt-account-id": accountId,
                "originator": originator,
                "Content-Type": "application/json",
                "Accept": "application/json",
            ],
            body: bodyData
        ))

        guard response.isSuccess else {
            let message = Self.backendErrorMessage(from: response.body)
            throw CodexError.backendError(statusCode: response.statusCode, message: message)
        }

        let value = try JSONDecoder().decode(JSONValue.self, from: response.body)
        guard case .object(let outer) = value,
              case .array(let items) = outer["output"] ?? .array([]) else {
            throw CodexError.invalidResponse
        }
        return items
    }

    /// `POST /codex/memories/trace_summarize` — summarize a batch of raw
    /// conversation traces into long-term memory entries.
    ///
    /// Used by Codex's "memories" feature. Returns the per-trace summary
    /// objects as ``JSONValue``.
    public func summarizeMemories(
        body: JSONValue,
        credentials: Credentials
    ) async throws -> [JSONValue] {
        guard let accountId = credentials.accountId, !accountId.isEmpty else {
            throw CodexError.missingAccountId
        }
        let url = baseURL.appendingPathComponent("codex/memories/trace_summarize")
        let bodyData = try JSONEncoder().encode(body)

        let response = try await httpClient.send(HTTPRequest(
            url: url,
            method: .post,
            headers: [
                "Authorization": "Bearer \(credentials.accessToken)",
                "chatgpt-account-id": accountId,
                "originator": originator,
                "Content-Type": "application/json",
                "Accept": "application/json",
            ],
            body: bodyData
        ))

        guard response.isSuccess else {
            let message = Self.backendErrorMessage(from: response.body)
            throw CodexError.backendError(statusCode: response.statusCode, message: message)
        }

        let value = try JSONDecoder().decode(JSONValue.self, from: response.body)
        guard case .object(let outer) = value,
              case .array(let items) = outer["output"] ?? .array([]) else {
            throw CodexError.invalidResponse
        }
        return items
    }

    /// Send a single prompt and stream the model's text deltas as they arrive.
    ///
    /// Each yielded `String` is one `response.output_text.delta` chunk from
    /// the backend's SSE stream — concatenate them to reconstruct the full
    /// reply. Throws on backend errors or non-2xx status codes.
    ///
    /// Cancelling the consuming `for try await` loop cancels the underlying
    /// HTTP task.
    public func streamTextResponse(
        prompt: String,
        instructions: String = "You are Codex, an AI coding assistant. Follow the user's request and respond concisely.",
        model: String = "gpt-5.5",
        credentials: Credentials
    ) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [urlSession, baseURL, originator] in
                do {
                    guard let accountId = credentials.accountId, !accountId.isEmpty else {
                        throw CodexError.missingAccountId
                    }

                    print("[CodexStream] enter prompt=\(prompt.prefix(40)) model=\(model)")
                    let url = baseURL.appendingPathComponent("codex/responses")
                    let requestBody: [String: Any] = [
                        "model": model,
                        "instructions": instructions,
                        "tools": [],
                        "tool_choice": "auto",
                        "parallel_tool_calls": false,
                        "store": false,
                        "stream": true,
                        "include": [],
                        "input": [
                            [
                                "role": "user",
                                "content": [
                                    [
                                        "type": "input_text",
                                        "text": prompt,
                                    ],
                                ],
                            ],
                        ],
                    ]
                    let body = try JSONSerialization.data(withJSONObject: requestBody)
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.httpBody = body
                    urlRequest.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
                    urlRequest.setValue(accountId, forHTTPHeaderField: "chatgpt-account-id")
                    urlRequest.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
                    urlRequest.setValue(originator, forHTTPHeaderField: "originator")
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    print("[CodexStream] awaiting bytes(for:) ...")
                    let (bytes, response) = try await urlSession.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw CodexError.invalidResponse
                    }
                    print("[CodexStream] got response status=\(http.statusCode) headers=\(http.allHeaderFields.count)")

                    guard (200..<300).contains(http.statusCode) else {
                        var errorBuffer = Data()
                        for try await byte in bytes { errorBuffer.append(byte) }
                        let message = Self.backendErrorMessage(from: errorBuffer)
                        throw CodexError.backendError(
                            statusCode: http.statusCode,
                            message: message
                        )
                    }

                    // SSE events are separated by blank lines. Accumulate
                    // each event's `data:` lines, then decode at the boundary.
                    // Yield text from any of the events the backend might use:
                    //   - response.output_text.delta  (the usual streaming case)
                    //   - response.output_item.done   (short replies sometimes arrive in one item)
                    //   - response.completed          (final fallback)
                    var current: [String] = []
                    var anyDeltaYielded = false
                    var pendingItemText: String?
                    var lineCount = 0
                    var eventCount = 0

                    func flushEvent() throws {
                        defer { current.removeAll(keepingCapacity: true) }
                        guard let event = Self.decodeSSEEvent(dataLines: current) else { return }
                        eventCount += 1
                        let type = event["type"] as? String ?? "<no-type>"
                        print("[CodexStream] event #\(eventCount) type=\(type)")
                        switch event["type"] as? String {
                        case "response.output_text.delta":
                            if let delta = event["delta"] as? String, !delta.isEmpty {
                                continuation.yield(delta)
                                anyDeltaYielded = true
                            }
                        case "response.output_item.done":
                            if !anyDeltaYielded,
                               let item = event["item"] as? [String: Any],
                               (item["role"] as? String) == "assistant",
                               let text = Self.outputText(from: item),
                               !text.isEmpty {
                                pendingItemText = text
                            }
                        case "response.completed":
                            if !anyDeltaYielded {
                                if let response = event["response"] as? [String: Any],
                                   let text = Self.outputText(from: response), !text.isEmpty {
                                    continuation.yield(text)
                                    anyDeltaYielded = true
                                } else if let text = pendingItemText {
                                    continuation.yield(text)
                                    anyDeltaYielded = true
                                }
                            }
                        case "response.failed", "response.incomplete":
                            throw CodexError.backendError(
                                statusCode: nil,
                                message: Self.backendErrorMessage(from: event)
                            )
                        default:
                            break
                        }
                    }

                    print("[CodexStream] entering line loop")
                    for try await line in bytes.lines {
                        lineCount += 1
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if lineCount <= 4 || lineCount % 25 == 0 {
                            print("[CodexStream] line #\(lineCount) prefix=\(trimmed.prefix(60))")
                        }
                        // The Codex backend's SSE stream omits the standard
                        // blank-line separator between events. Each event is
                        // just `event: <name>\ndata: <json>` with no
                        // terminator. Treat either an empty line OR the next
                        // `event:` header as the boundary that finalises the
                        // previous event.
                        if trimmed.isEmpty || trimmed.hasPrefix("event:") {
                            try flushEvent()
                        } else if trimmed.hasPrefix("data:") {
                            current.append(
                                String(trimmed.dropFirst("data:".count))
                                    .trimmingCharacters(in: .whitespaces)
                            )
                        }
                    }
                    try flushEvent()
                    print("[CodexStream] finish lines=\(lineCount) events=\(eventCount) anyDelta=\(anyDeltaYielded) pending=\(pendingItemText?.count ?? 0)")
                    if !anyDeltaYielded, let text = pendingItemText {
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func decodeSSEEvent(dataLines: [String]) -> [String: Any]? {
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func outputText(from json: [String: Any]) -> String? {
        if let text = json["output_text"] as? String {
            return text
        }

        var chunks: [String] = []
        if let content = json["content"] as? [[String: Any]] {
            for contentItem in content {
                if let text = contentItem["text"] as? String,
                   contentItem["type"] as? String == "output_text" {
                    chunks.append(text)
                }
            }
        }
        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                if let content = item["content"] as? [[String: Any]] {
                    for contentItem in content {
                        if let text = contentItem["text"] as? String,
                           contentItem["type"] as? String == "output_text" {
                            chunks.append(text)
                        }
                    }
                }
            }
        }

        let joined = chunks.joined()
        return joined.isEmpty ? nil : joined
    }

    private static func parseResponse(from data: Data) throws -> OpenAICodexResponse {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = outputText(from: json) {
            return OpenAICodexResponse(text: text, responseId: json["id"] as? String)
        }

        guard let stream = String(data: data, encoding: .utf8) else {
            throw CodexError.invalidResponse
        }

        var deltas = ""
        var completedText: String?
        var responseId: String?
        for payload in sseDataPayloads(from: stream) {
            guard let eventData = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                  let type = event["type"] as? String else {
                continue
            }

            switch type {
            case "response.created":
                if let response = event["response"] as? [String: Any] {
                    responseId = response["id"] as? String ?? responseId
                }
            case "response.output_text.delta":
                deltas += event["delta"] as? String ?? ""
            case "response.output_item.done":
                if let item = event["item"] as? [String: Any],
                   item["role"] as? String == "assistant",
                   let text = outputText(from: item) {
                    completedText = text
                }
            case "response.completed":
                if let response = event["response"] as? [String: Any] {
                    responseId = response["id"] as? String ?? responseId
                    completedText = outputText(from: response) ?? completedText
                }
            case "response.failed", "response.incomplete":
                throw CodexError.backendError(statusCode: nil, message: backendErrorMessage(from: event))
            default:
                break
            }
        }

        let text = deltas.isEmpty ? completedText : deltas
        guard let text, !text.isEmpty else {
            throw CodexError.invalidResponse
        }
        return OpenAICodexResponse(text: text, responseId: responseId)
    }

    private static func sseDataPayloads(from stream: String) -> [String] {
        stream
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .compactMap { event in
                let dataLines = event
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .compactMap { line -> String? in
                        guard line.hasPrefix("data:") else { return nil }
                        return String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                    }
                guard !dataLines.isEmpty else { return nil }
                return dataLines.joined(separator: "\n")
            }
    }

    private static func backendErrorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }

        if let message = json["message"] as? String {
            return message
        }
        if let detail = json["detail"] as? String {
            return detail
        }
        if let detail = json["detail"] as? [String: Any],
           let message = detail["message"] as? String {
            return message
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    private static func backendErrorMessage(from json: [String: Any]) -> String {
        if let message = json["message"] as? String {
            return message
        }
        if let response = json["response"] as? [String: Any],
           let error = response["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return "Unknown streaming response error"
    }
}
