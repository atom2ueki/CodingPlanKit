// OpenAICodexClient.swift
// CodingPlanAuthKit

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
    private let baseURL: URL
    private let originator: String

    /// Create a new client.
    /// - Parameters:
    ///   - httpClient: HTTP transport. Defaults to ``URLSessionHTTPClient``.
    ///   - baseURL: Backend base URL. Defaults to ``OpenAIBackend/defaultBaseURL``.
    ///   - originator: Originator header. Defaults to ``OpenAIBackend/defaultOriginator``.
    public init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        baseURL: URL = OpenAIBackend.defaultBaseURL,
        originator: String = OpenAIBackend.defaultOriginator
    ) {
        self.httpClient = httpClient
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
            throw AuthError.notAuthenticated
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
            throw AuthError.serverError("Codex backend returned \(response.statusCode): \(message)")
        }

        return try Self.parseResponse(from: response.body)
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
            let task = Task {
                do {
                    guard let accountId = credentials.accountId, !accountId.isEmpty else {
                        throw AuthError.notAuthenticated
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

                    let streaming = try await httpClient.sendStreaming(HTTPRequest(
                        url: url,
                        method: .post,
                        headers: headers,
                        body: body
                    ))

                    guard streaming.isSuccess else {
                        var errorBuffer = Data()
                        for try await chunk in streaming.body { errorBuffer.append(chunk) }
                        let message = Self.backendErrorMessage(from: errorBuffer)
                        throw AuthError.serverError(
                            "Codex backend returned \(streaming.statusCode): \(message)"
                        )
                    }

                    var pending = ""
                    for try await chunk in streaming.body {
                        guard let text = String(data: chunk, encoding: .utf8) else { continue }
                        pending.append(text)
                        while let separator = Self.firstEventBoundary(in: pending) {
                            let event = String(pending[..<separator.lowerBound])
                            pending.removeSubrange(..<separator.upperBound)
                            if let delta = Self.delta(from: event) {
                                continuation.yield(delta)
                            }
                        }
                    }
                    if !pending.isEmpty, let delta = Self.delta(from: pending) {
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func firstEventBoundary(in buffer: String) -> Range<String.Index>? {
        if let r = buffer.range(of: "\n\n") { return r }
        if let r = buffer.range(of: "\r\n\r\n") { return r }
        return nil
    }

    private static func delta(from event: String) -> String? {
        let dataLines: [String] = event
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                guard line.hasPrefix("data:") else { return nil }
                return String(line.dropFirst("data:".count))
                    .trimmingCharacters(in: .whitespaces)
            }
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        guard let payloadData = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let type = json["type"] as? String,
              type == "response.output_text.delta",
              let chunk = json["delta"] as? String else {
            return nil
        }
        return chunk
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
            throw AuthError.invalidResponse
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
                throw AuthError.serverError(backendErrorMessage(from: event))
            default:
                break
            }
        }

        let text = deltas.isEmpty ? completedText : deltas
        guard let text, !text.isEmpty else {
            throw AuthError.invalidResponse
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
