import Foundation
import Testing
import CodingPlanAuth
@testable import CodingPlanCodex

struct SendAddCreditsNudgeTests {
    @Test
    func sendsExpectedRequestForCreditsNudge() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/accounts/send_add_credits_nudge_email")!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: Data(), statusCode: 200)

        let client = OpenAICodexUsageClient(httpClient: httpClient)
        let credentials = Credentials(accessToken: "access-token", accountId: "account-123")

        try await client.sendAddCreditsNudgeEmail(creditType: .credits, credentials: credentials)

        let recorded = await httpClient.recordedRequests()
        let request = try #require(recorded.first)
        #expect(request.url == endpoint)
        #expect(request.method == .post)
        #expect(request.headers["Authorization"] == "Bearer access-token")
        #expect(request.headers["ChatGPT-Account-Id"] == "account-123")
        #expect(request.headers["Content-Type"] == "application/json")

        let body = try #require(request.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["credit_type"] as? String == "Credits")
    }

    @Test
    func sendsUsageLimitNudge() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/accounts/send_add_credits_nudge_email")!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: Data(), statusCode: 200)

        let client = OpenAICodexUsageClient(httpClient: httpClient)
        let credentials = Credentials(accessToken: "access-token", accountId: "account-123")

        try await client.sendAddCreditsNudgeEmail(creditType: .usageLimit, credentials: credentials)

        let recorded = await httpClient.recordedRequests()
        let body = try #require(recorded.first?.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["credit_type"] as? String == "UsageLimit")
    }

    @Test
    func nudgeRequiresAccountId() async throws {
        let client = OpenAICodexUsageClient()
        await #expect(throws: CodexError.missingAccountId) {
            try await client.sendAddCreditsNudgeEmail(
                creditType: .credits,
                credentials: Credentials(accessToken: "access-token")
            )
        }
    }
}
