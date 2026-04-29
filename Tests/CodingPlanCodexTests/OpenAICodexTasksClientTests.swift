import Foundation
import Testing
import CodingPlanAuth
@testable import CodingPlanCodex

struct OpenAICodexTasksClientTests {
    private let credentials = Credentials(accessToken: "access-token", accountId: "account-123")

    @Test
    func listTasksBuildsExpectedRequestAndDecodesItems() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/tasks/list?limit=20&task_filter=open&cursor=abc")!
        let payload = """
        {
            "items": [
                {
                    "id": "task_1",
                    "title": "Refactor auth flow",
                    "archived": false,
                    "has_unread_turn": true,
                    "has_generated_title": true,
                    "created_at": 1700000000.5,
                    "updated_at": 1700000060.0,
                    "task_status_display": {"label": "running", "color": "green"},
                    "pull_requests": []
                },
                {
                    "id": "task_2",
                    "title": "Add tests",
                    "archived": true,
                    "has_unread_turn": false
                }
            ],
            "cursor": "next_page_cursor"
        }
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: payload, statusCode: 200)

        let client = OpenAICodexTasksClient(httpClient: httpClient)
        let page = try await client.listTasks(limit: 20, filter: "open", cursor: "abc", credentials: credentials)

        #expect(page.items.count == 2)
        #expect(page.cursor == "next_page_cursor")
        #expect(page.items[0].id == "task_1")
        #expect(page.items[0].title == "Refactor auth flow")
        #expect(page.items[0].archived == false)
        #expect(page.items[0].hasUnreadTurn == true)
        #expect(page.items[0].hasGeneratedTitle == true)
        #expect(page.items[0].createdAt == Date(timeIntervalSince1970: 1_700_000_000.5))
        #expect(page.items[0].updatedAt == Date(timeIntervalSince1970: 1_700_000_060.0))
        #expect(page.items[1].archived == true)
        #expect(page.items[1].hasGeneratedTitle == nil)
    }

    @Test
    func getTaskReturnsRawJSONAndDecodedShape() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/tasks/task_42")!
        let payload = """
        {"current_user_turn":{"id":"turn_1"},"current_assistant_turn":null}
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: payload, statusCode: 200)

        let client = OpenAICodexTasksClient(httpClient: httpClient)
        let details = try await client.getTask(id: "task_42", credentials: credentials)

        #expect(details.rawJSON == payload)
        let userTurnId = details.json["current_user_turn"]?["id"]
        if case .string(let id) = userTurnId {
            #expect(id == "turn_1")
        } else {
            Issue.record("expected current_user_turn.id to decode as string")
        }
    }

    @Test
    func getSiblingTurnsExtractsSiblingTurnsArray() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/tasks/task_42/turns/turn_5/sibling_turns")!
        let payload = """
        {"sibling_turns":[{"id":"turn_5a"},{"id":"turn_5b"}]}
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: payload, statusCode: 200)

        let client = OpenAICodexTasksClient(httpClient: httpClient)
        let result = try await client.getSiblingTurns(taskId: "task_42", turnId: "turn_5", credentials: credentials)

        #expect(result.siblingTurns.count == 2)
    }

    @Test
    func createTaskExtractsNestedTaskId() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/tasks")!
        let payload = """
        {"task":{"id":"task_new"}}
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: payload, statusCode: 200)

        let client = OpenAICodexTasksClient(httpClient: httpClient)
        let body: JSONValue = .object(["prompt": .string("hello"), "environment_id": .string("env_1")])
        let id = try await client.createTask(body: body, credentials: credentials)

        #expect(id == "task_new")

        let recorded = await httpClient.recordedRequests()
        let request = try #require(recorded.first)
        #expect(request.method == .post)
        #expect(request.headers["Content-Type"] == "application/json")
    }

    @Test
    func createTaskFallsBackToTopLevelId() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/tasks")!
        let payload = #"{"id":"task_top"}"#.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: payload, statusCode: 200)

        let client = OpenAICodexTasksClient(httpClient: httpClient)
        let id = try await client.createTask(body: .object([:]), credentials: credentials)
        #expect(id == "task_top")
    }

    @Test
    func tasksRequireAccountId() async throws {
        let client = OpenAICodexTasksClient()
        await #expect(throws: CodexError.missingAccountId) {
            _ = try await client.listTasks(credentials: Credentials(accessToken: "access-token"))
        }
    }
}
