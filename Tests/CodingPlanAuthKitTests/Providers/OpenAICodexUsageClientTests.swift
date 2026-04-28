import Foundation
import Testing
@testable import CodingPlanAuthKit

struct OpenAICodexUsageClientTests {
    @Test
    func fetchRateLimitsBuildsExpectedRequestAndMapsWindows() async throws {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        let response = """
        {
            "plan_type": "pro",
            "rate_limit": {
                "allowed": true,
                "limit_reached": false,
                "primary_window": {
                    "used_percent": 42,
                    "limit_window_seconds": 18000,
                    "reset_after_seconds": 0,
                    "reset_at": 1777104000
                },
                "secondary_window": {
                    "used_percent": 84,
                    "limit_window_seconds": 604800,
                    "reset_after_seconds": 0,
                    "reset_at": 1777500000
                }
            },
            "credits": {
                "has_credits": true,
                "unlimited": false,
                "balance": "9.99"
            },
            "additional_rate_limits": [
                {
                    "limit_name": "codex_other",
                    "metered_feature": "codex_other",
                    "rate_limit": {
                        "allowed": true,
                        "limit_reached": false,
                        "primary_window": {
                            "used_percent": 70,
                            "limit_window_seconds": 900,
                            "reset_after_seconds": 0,
                            "reset_at": 1777100000
                        }
                    }
                }
            ],
            "rate_limit_reached_type": {
                "type": "workspace_member_credits_depleted"
            }
        }
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient()
        await httpClient.setResponse(for: endpoint, data: response, statusCode: 200)

        let client = OpenAICodexUsageClient(httpClient: httpClient)
        let credentials = Credentials(
            accessToken: "access-token",
            accountId: "account-123"
        )

        let limits = try await client.fetchRateLimits(credentials: credentials)

        #expect(limits.rateLimits.limitId == "codex")
        #expect(limits.rateLimits.planType == "pro")
        #expect(limits.rateLimits.primary?.usedPercent == 42)
        #expect(limits.rateLimits.primary?.remainingPercent == 58)
        #expect(limits.rateLimits.primary?.windowDurationMinutes == 300)
        #expect(limits.rateLimits.primary?.resetsAt == Date(timeIntervalSince1970: 1_777_104_000))
        #expect(limits.rateLimits.secondary?.usedPercent == 84)
        #expect(limits.rateLimits.secondary?.windowDurationMinutes == 10_080)
        #expect(limits.rateLimits.credits?.balance == "9.99")
        #expect(limits.rateLimits.rateLimitReachedType == "workspace_member_credits_depleted")
        #expect(limits.rateLimitsByLimitId["codex_other"]?.primary?.windowDurationMinutes == 15)

        let requests = await httpClient.recordedRequests()
        let request = try #require(requests.first)
        #expect(request.url == endpoint)
        #expect(request.method == "GET")
        #expect(request.body == nil)
        #expect(request.headers["Authorization"] == "Bearer access-token")
        #expect(request.headers["ChatGPT-Account-Id"] == "account-123")
        #expect(request.headers["originator"] == "codex_cli_rs")
        #expect(request.headers["Accept"] == "application/json")
    }

    @Test
    func fetchRateLimitsRequiresAccountId() async throws {
        let client = OpenAICodexUsageClient()
        await #expect(throws: AuthError.notAuthenticated) {
            _ = try await client.fetchRateLimits(credentials: Credentials(accessToken: "access-token"))
        }
    }
}
