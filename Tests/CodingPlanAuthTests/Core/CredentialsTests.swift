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
    func credentialsAreExpiredWithinDefaultLeewayWindow() {
        // The whole point of the 60s leeway is to refresh *before* the
        // token actually expires, so a request in flight doesn't 401
        // due to clock skew. A token expiring in 30s must already
        // count as expired so `AuthService.credentials(for:)` triggers
        // a refresh.
        let almostExpired = Date().addingTimeInterval(30)
        let creds = Credentials(accessToken: "abc", expiresAt: almostExpired)
        #expect(creds.isExpired)
    }

    @Test
    func customLeewayChangesTheExpiryThreshold() {
        let in90Seconds = Date().addingTimeInterval(90)
        let creds = Credentials(accessToken: "abc", expiresAt: in90Seconds)
        #expect(!creds.isExpired(leeway: 60))
        #expect(creds.isExpired(leeway: 120))
    }

    @Test
    func persistedJSONKeysAreStable() throws {
        // These keys are persisted to Keychain via `KeychainTokenStorage`.
        // Any rename silently signs every existing user out on the next
        // app launch, since the old payload won't decode into the new
        // shape. If a rename is intentional, also bump a storage version
        // and migrate.
        let creds = Credentials(
            accessToken: "at",
            refreshToken: "rt",
            idToken: "id",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
            tokenType: .bearer,
            accountId: "acc-1",
            accountEmail: "test@example.com",
            accountPlanType: "plus"
        )
        let encoded = try JSONEncoder().encode(creds)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let keys = Set((json ?? [:]).keys)
        #expect(keys.contains("accessToken"))
        #expect(keys.contains("refreshToken"))
        #expect(keys.contains("idToken"))
        #expect(keys.contains("expiresAt"))
        #expect(keys.contains("tokenType"))
        #expect(keys.contains("accountId"))
        #expect(keys.contains("accountEmail"))
        #expect(keys.contains("accountPlanType"))
    }
}
