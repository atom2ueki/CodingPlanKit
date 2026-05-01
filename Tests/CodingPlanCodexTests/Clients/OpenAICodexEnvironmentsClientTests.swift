import Foundation
import Testing
import CodingPlanAuth
@testable import CodingPlanCodex

struct OpenAICodexEnvironmentsClientTests {
    private let credentials = Credentials(accessToken: "access-token", accountId: "account-123")

    @Test
    func listEnvironmentsDecodesArray() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/environments")!
        let payload = """
        [
            {"id":"env_1","label":"Default","is_pinned":true,"task_count":4},
            {"id":"env_2","label":null}
        ]
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: payload, statusCode: 200)

        let client = OpenAICodexEnvironmentsClient(httpClient: httpClient)
        let envs = try await client.listEnvironments(credentials: credentials)

        #expect(envs.count == 2)
        #expect(envs[0].id == "env_1")
        #expect(envs[0].label == "Default")
        #expect(envs[0].isPinned == true)
        #expect(envs[0].taskCount == 4)
        #expect(envs[1].label == nil)
        #expect(envs[1].taskCount == nil)
    }

    @Test
    func listEnvironmentsByRepoBuildsExpectedPath() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/environments/by-repo/github/atom2ueki/CodingPlanKit")!
        let payload = #"[{"id":"env_repo","label":"Repo env"}]"#.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: payload, statusCode: 200)

        let client = OpenAICodexEnvironmentsClient(httpClient: httpClient)
        let envs = try await client.listEnvironments(
            provider: "github",
            owner: "atom2ueki",
            repo: "CodingPlanKit",
            credentials: credentials
        )

        #expect(envs.count == 1)
        #expect(envs[0].id == "env_repo")

        let recorded = await httpClient.recordedRequests()
        #expect(recorded.first?.url == endpoint)
    }

    @Test
    func fetchConfigRequirementsDecodesAllFields() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/config/requirements")!
        let payload = """
        {
            "contents": "pip install -r requirements.txt",
            "sha256": "abc123",
            "updated_at": "2025-01-15T10:00:00Z",
            "updated_by_user_id": "user_1"
        }
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: payload, statusCode: 200)

        let client = OpenAICodexEnvironmentsClient(httpClient: httpClient)
        let config = try await client.fetchConfigRequirements(credentials: credentials)

        #expect(config.contents == "pip install -r requirements.txt")
        #expect(config.sha256 == "abc123")
        #expect(config.updatedAt == "2025-01-15T10:00:00Z")
        #expect(config.updatedByUserId == "user_1")
    }

    @Test
    func environmentsRequireAccountId() async throws {
        let client = OpenAICodexEnvironmentsClient()
        await #expect(throws: CodexError.missingAccountId) {
            _ = try await client.listEnvironments(credentials: Credentials(accessToken: "access-token"))
        }
    }
}
