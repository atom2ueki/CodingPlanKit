import Foundation
import Testing
@testable import CodingPlanAuth

struct CredentialsTests {
    @Test
    func credentialsAreNotExpiredWhenNoExpirySet() {
        let creds = Credentials(accessToken: "abc")
        #expect(!creds.isExpired)
    }

    @Test
    func credentialsAreExpiredWhenPastExpiry() {
        let past = Date().addingTimeInterval(-120)
        let creds = Credentials(accessToken: "abc", expiresAt: past)
        #expect(creds.isExpired)
    }

    @Test
    func credentialsAreNotExpiredWhenWellBeforeExpiry() {
        let future = Date().addingTimeInterval(300)
        let creds = Credentials(accessToken: "abc", expiresAt: future)
        #expect(!creds.isExpired)
    }

    @Test
    func equalityAndCodingRoundTrip() throws {
        let original = Credentials(
            accessToken: "at",
            refreshToken: "rt",
            idToken: "id",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
            tokenType: "Bearer",
            accountId: "acc-1",
            accountEmail: "test@example.com",
            accountPlanType: "plus"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Credentials.self, from: data)
        #expect(original == decoded)
    }
}
