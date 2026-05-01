import Foundation
import Testing
import CodingPlanAuth
@testable import CodingPlanCodex

struct OpenAICodexClientTests {
    @Test
    func createTextResponseBuildsExpectedRequest() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
        let responseStream = """
        data: {"type":"response.created","response":{"id":"resp_123"}}

        data: {"type":"response.output_text.delta","delta":"po"}

        data: {"type":"response.output_text.delta","delta":"ng"}

        data: {"type":"response.completed","response":{"id":"resp_123","usage":{"input_tokens":0,"output_tokens":0,"total_tokens":0}}}

        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: responseStream, statusCode: 200)

        let client = OpenAICodexClient(httpClient: httpClient)
        let credentials = Credentials(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "bearer",
            accountId: "account-123",
            accountEmail: "u@example.com",
            accountPlanType: "plus"
        )

        let response = try await client.createTextResponse(
            prompt: "ping",
            credentials: credentials
        )

        #expect(response.responseId == "resp_123")
        #expect(response.text == "pong")

        let requests = await httpClient.recordedRequests()
        let request = try #require(requests.first)
        #expect(request.url == endpoint)
        #expect(request.method == .post)
        #expect(request.headers["Authorization"] == "Bearer access-token")
        #expect(request.headers["chatgpt-account-id"] == "account-123")
        #expect(request.headers["OpenAI-Beta"] == "responses=experimental")
        #expect(request.headers["originator"] == "codex_cli_rs")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Accept"] == "text/event-stream")

        let body = try #require(request.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-5.5")
        #expect(json["instructions"] as? String == "You are Codex, an AI coding assistant. Follow the user's request and respond concisely.")
        #expect(json["stream"] as? Bool == true)
        #expect(json["tool_choice"] as? String == "auto")
        #expect(json["parallel_tool_calls"] as? Bool == false)

        let tools = try #require(json["tools"] as? [Any])
        #expect(tools.isEmpty)

        let include = try #require(json["include"] as? [Any])
        #expect(include.isEmpty)

        let input = try #require(json["input"] as? [[String: Any]])
        let message = try #require(input.first)
        #expect(message["role"] as? String == "user")

        let content = try #require(message["content"] as? [[String: Any]])
        let contentItem = try #require(content.first)
        #expect(contentItem["type"] as? String == "input_text")
        #expect(contentItem["text"] as? String == "ping")
    }

    @Test
    func createTextResponseParsesAdjacentSSEEvents() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
        let responseStream = """
        event: response.created
        data: {"type":"response.created","response":{"id":"resp_456"}}
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"po"}
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"ng"}
        event: response.completed
        data: {"type":"response.completed","response":{"id":"resp_456"}}
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: responseStream, statusCode: 200)

        let client = OpenAICodexClient(httpClient: httpClient)
        let credentials = Credentials(accessToken: "access-token", accountId: "account-123")

        let response = try await client.createTextResponse(
            prompt: "ping",
            credentials: credentials
        )

        #expect(response.responseId == "resp_456")
        #expect(response.text == "pong")
    }
}
