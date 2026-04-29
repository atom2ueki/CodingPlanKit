import Foundation
import Testing
import CodingPlanAuth
@testable import CodingPlanCodex

struct CompactAndMemoriesTests {
    private let credentials = Credentials(accessToken: "access-token", accountId: "account-123")

    @Test
    func compactExtractsOutputArray() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/responses/compact")!
        let payload = #"{"output":[{"type":"summary","text":"compacted"}]}"#.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: payload, statusCode: 200)

        let client = OpenAICodexClient(httpClient: httpClient)
        let items = try await client.compactResponse(
            body: .object(["model": .string("gpt-5.5"), "input": .array([])]),
            credentials: credentials
        )

        #expect(items.count == 1)
        if case .object(let dict) = items[0], case .string(let type) = dict["type"] ?? .null {
            #expect(type == "summary")
        } else {
            Issue.record("expected output[0].type to be string")
        }

        let recorded = await httpClient.recordedRequests()
        let request = try #require(recorded.first)
        #expect(request.method == .post)
        #expect(request.headers["chatgpt-account-id"] == "account-123")
    }

    @Test
    func memoriesPostsToTraceSummarize() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/memories/trace_summarize")!
        let payload = #"{"output":[{"trace_summary":"sum"}]}"#.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: payload, statusCode: 200)

        let client = OpenAICodexClient(httpClient: httpClient)
        let summaries = try await client.summarizeMemories(
            body: .object(["model": .string("gpt-5.5"), "raw_memories": .array([])]),
            credentials: credentials
        )

        #expect(summaries.count == 1)
        let recorded = await httpClient.recordedRequests()
        #expect(recorded.first?.url == endpoint)
    }

    @Test
    func compactRequiresAccountId() async throws {
        let client = OpenAICodexClient()
        await #expect(throws: CodexError.missingAccountId) {
            _ = try await client.compactResponse(
                body: .object([:]),
                credentials: Credentials(accessToken: "access-token")
            )
        }
    }
}
