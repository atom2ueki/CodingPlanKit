import Foundation
@testable import CodingPlanAuthKit

actor MockTokenStorage: TokenStorage {
    private var store: [String: Credentials] = [:]

    func save(credentials: Credentials, for providerId: String) async throws {
        store[providerId] = credentials
    }

    func load(for providerId: String) async throws -> Credentials? {
        store[providerId]
    }

    func delete(for providerId: String) async throws {
        store.removeValue(forKey: providerId)
    }

    func hasCredentials(for providerId: String) -> Bool {
        store[providerId] != nil
    }
}
