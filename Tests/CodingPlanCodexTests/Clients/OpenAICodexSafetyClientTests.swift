import Foundation
import Testing
import CodingPlanAuth
@testable import CodingPlanCodex

struct OpenAICodexSafetyClientTests {
    @Test
    func evaluateWithMonitorTokenSendsBearerHeader() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/safety/arc")!
        let payload = """
        {
            "outcome": "ok",
            "short_reason": "",
            "rationale": "no risk",
            "risk_score": 5,
            "risk_level": "low",
            "evidence": []
        }
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: payload, statusCode: 200)

        let client = OpenAICodexSafetyClient(httpClient: httpClient)
        let result = try await client.evaluate(
            body: .object(["action": .object([:])]),
            auth: .monitorToken("monitor-token-abc")
        )

        #expect(result.outcome == .ok)
        #expect(result.riskScore == 5)
        #expect(result.riskLevel == .low)

        let recorded = await httpClient.recordedRequests()
        let request = try #require(recorded.first)
        #expect(request.headers["Authorization"] == "Bearer monitor-token-abc")
        #expect(request.headers["ChatGPT-Account-Id"] == nil)
    }

    @Test
    func evaluateWithCredentialsSendsAccountIdHeader() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/safety/arc")!
        let payload = """
        {
            "outcome": "ask-user",
            "short_reason": "destructive",
            "rationale": "rm -rf",
            "risk_score": 80,
            "risk_level": "high",
            "evidence": [{"message":"rm -rf /","why":"data loss"}]
        }
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: payload, statusCode: 200)

        let client = OpenAICodexSafetyClient(httpClient: httpClient)
        let credentials = Credentials(accessToken: "access-token", accountId: "account-123")
        let result = try await client.evaluate(
            body: .object(["action": .object([:])]),
            auth: .planCredentials(credentials)
        )

        #expect(result.outcome == .askUser)
        #expect(result.riskLevel == .high)
        #expect(result.evidence.count == 1)
        #expect(result.evidence[0].message == "rm -rf /")

        let recorded = await httpClient.recordedRequests()
        let request = try #require(recorded.first)
        #expect(request.headers["Authorization"] == "Bearer access-token")
        #expect(request.headers["ChatGPT-Account-Id"] == "account-123")
    }

    @Test
    func planCredentialsRequireAccountId() async throws {
        let client = OpenAICodexSafetyClient()
        await #expect(throws: CodexError.missingAccountId) {
            _ = try await client.evaluate(
                body: .object([:]),
                auth: .planCredentials(Credentials(accessToken: "access-token"))
            )
        }
    }
}
