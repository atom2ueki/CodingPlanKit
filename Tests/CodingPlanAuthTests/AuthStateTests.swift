import Foundation
import Testing
@testable import CodingPlanAuth

@MainActor
struct AuthStateTests {
    @Test
    func checkStatusClearsAuthenticatedStateWhenRefreshFails() async throws {
        let storage = MockTokenStorage()
        let service = AuthService(storage: storage)
        let provider = MockAuthProvider(id: "openai", name: "OpenAI")
        await service.register(provider)

        try await storage.save(
            credentials: Credentials(
                accessToken: "valid",
                refreshToken: "rt",
                expiresAt: Date().addingTimeInterval(3600)
            ),
            for: "openai"
        )

        let state = AuthState(service: service, providerId: "openai")
        await state.checkStatus()
        #expect(state.isAuthenticated)
        #expect(state.currentCredentials?.accessToken == "valid")

        let refreshError = AuthError.tokenExchangeFailed(statusCode: 401, message: "expired")
        await provider.setShouldThrowOnRefresh(refreshError)
        try await storage.save(
            credentials: Credentials(
                accessToken: "expired",
                refreshToken: "rt",
                expiresAt: Date().addingTimeInterval(-100)
            ),
            for: "openai"
        )

        await state.checkStatus()

        #expect(!state.isAuthenticated)
        #expect(state.currentCredentials == nil)
        #expect(state.lastError == refreshError)
    }

    @Test
    func checkStatusKeepsAuthenticatedStateWhenRefreshNetworkFails() async throws {
        let storage = MockTokenStorage()
        let service = AuthService(storage: storage)
        let provider = MockAuthProvider(id: "openai", name: "OpenAI")
        await service.register(provider)

        try await storage.save(
            credentials: Credentials(
                accessToken: "valid",
                refreshToken: "rt",
                expiresAt: Date().addingTimeInterval(3600)
            ),
            for: "openai"
        )

        let state = AuthState(service: service, providerId: "openai")
        await state.checkStatus()
        #expect(state.isAuthenticated)
        #expect(state.currentCredentials?.accessToken == "valid")

        let refreshError = AuthError.networkError("offline")
        await provider.setShouldThrowOnRefresh(refreshError)
        try await storage.save(
            credentials: Credentials(
                accessToken: "expired",
                refreshToken: "rt",
                expiresAt: Date().addingTimeInterval(-100)
            ),
            for: "openai"
        )

        await state.checkStatus()

        #expect(state.isAuthenticated)
        #expect(state.currentCredentials?.accessToken == "valid")
        #expect(state.lastError == refreshError)
    }
}
