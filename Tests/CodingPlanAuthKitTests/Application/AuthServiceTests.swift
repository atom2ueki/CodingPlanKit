import Foundation
import Testing
@testable import CodingPlanAuthKit

struct AuthServiceTests {
    @Test
    func isAuthenticatedReturnsFalseWhenNoCredentials() async throws {
        let storage = MockTokenStorage()
        let service = AuthService(storage: storage)
        let result = try await service.isAuthenticated(providerId: "openai")
        #expect(!result)
    }

    @Test
    func isAuthenticatedReturnsTrueWhenCredentialsExist() async throws {
        let storage = MockTokenStorage()
        let service = AuthService(storage: storage)
        let provider = MockAuthProvider(id: "openai", name: "OpenAI")
        await service.register(provider)

        let creds = Credentials(accessToken: "abc")
        try await storage.save(credentials: creds, for: "openai")

        let result = try await service.isAuthenticated(providerId: "openai")
        #expect(result)
    }

    @Test
    func credentialsAutoRefreshesWhenExpired() async throws {
        let storage = MockTokenStorage()
        let service = AuthService(storage: storage)
        let provider = MockAuthProvider(id: "openai", name: "OpenAI")
        await provider.setNextCredentials(Credentials(
            accessToken: "fresh",
            refreshToken: "rt2",
            expiresAt: Date().addingTimeInterval(3600)
        ))
        await service.register(provider)

        let expired = Credentials(
            accessToken: "old",
            refreshToken: "rt",
            expiresAt: Date().addingTimeInterval(-100)
        )
        try await storage.save(credentials: expired, for: "openai")

        let result = try await service.credentials(for: "openai")
        #expect(result?.accessToken == "fresh")
        let stored = try await storage.load(for: "openai")
        #expect(stored?.accessToken == "fresh")
    }

    @Test
    func completeLoginPersistsCredentials() async throws {
        let storage = MockTokenStorage()
        let service = AuthService(storage: storage)
        let provider = MockAuthProvider(id: "openai", name: "OpenAI")
        await service.register(provider)

        let session = MockLoginSession(
            providerId: "openai",
            authURL: URL(string: "https://example.com")!,
            credentials: Credentials(accessToken: "new")
        )
        await provider.setNextSession(session)

        let beginSession = try await service.beginLogin(providerId: "openai")
        let callbackURL = URL(string: "https://example.com/callback?code=123")!
        let creds = try await service.completeLogin(
            session: beginSession,
            with: callbackURL
        )

        #expect(creds.accessToken == "new")
        let stored = try await storage.load(for: "openai")
        #expect(stored?.accessToken == "new")
    }

    @Test
    func logoutDeletesCredentials() async throws {
        let storage = MockTokenStorage()
        let service = AuthService(storage: storage)
        let provider = MockAuthProvider(id: "openai", name: "OpenAI")
        await service.register(provider)

        try await storage.save(credentials: Credentials(accessToken: "x"), for: "openai")
        try await service.logout(providerId: "openai")

        let stored = try await storage.load(for: "openai")
        #expect(stored == nil)
    }

    @Test
    func unsupportedProviderThrows() async throws {
        let storage = MockTokenStorage()
        let service = AuthService(storage: storage)

        await #expect(throws: AuthError.unsupportedProvider) {
            _ = try await service.beginLogin(providerId: "unknown")
        }
    }
}
