import Foundation
import Testing
import CodingPlanAuth
@testable import CodingPlanCodex

struct OpenAICodexModelsClientTests {
    @Test
    func listModelsBuildsExpectedRequestAndDecodesEntries() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/models?client_version=0.99.0")!
        let payload = """
        {
            "models": [
                {
                    "slug": "gpt-5.5",
                    "display_name": "GPT-5.5",
                    "description": "Default Codex model",
                    "context_window": 272000,
                    "supported_in_api": true,
                    "priority": 1,
                    "visibility": "list",
                    "default_reasoning_level": "medium"
                },
                {
                    "slug": "gpt-experimental",
                    "display_name": "Experimental",
                    "supported_in_api": false,
                    "visibility": "experimental"
                }
            ]
        }
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: payload, statusCode: 200)

        let client = OpenAICodexModelsClient(httpClient: httpClient)
        let credentials = Credentials(accessToken: "access-token", accountId: "account-123")

        let (models, etag) = try await client.listModels(clientVersion: "0.99.0", credentials: credentials)

        #expect(models.count == 2)
        #expect(models[0].slug == "gpt-5.5")
        #expect(models[0].displayName == "GPT-5.5")
        #expect(models[0].contextWindow == 272_000)
        #expect(models[0].priority == 1)
        #expect(models[0].visibility == .list)
        #expect(models[0].defaultReasoningLevel == "medium")
        #expect(models[1].supportedInApi == false)
        #expect(models[1].visibility == .experimental)
        #expect(etag == nil)

        let recorded = await httpClient.recordedRequests()
        let request = try #require(recorded.first)
        #expect(request.url == endpoint)
        #expect(request.method == .get)
        #expect(request.headers["Authorization"] == "Bearer access-token")
        #expect(request.headers["ChatGPT-Account-Id"] == "account-123")
        #expect(request.headers["originator"] == "codex_cli_rs")
    }

    @Test
    func listModelsRequiresAccountId() async throws {
        let client = OpenAICodexModelsClient()
        await #expect(throws: CodexError.missingAccountId) {
            _ = try await client.listModels(
                clientVersion: "0.99.0",
                credentials: Credentials(accessToken: "access-token")
            )
        }
    }
}
