import Foundation
@testable import CodingPlanAuthKit

actor MockAuthProvider: AuthProvider {
    let id: String
    let name: String

    private var nextSession: (any LoginSession)?
    private var nextCredentials: Credentials?
    private var shouldThrowOnBegin: AuthError?
    private var shouldThrowOnRefresh: AuthError?

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    func setNextSession(_ session: any LoginSession) {
        self.nextSession = session
    }

    func setNextCredentials(_ credentials: Credentials) {
        self.nextCredentials = credentials
    }

    func setShouldThrowOnBegin(_ error: AuthError?) {
        self.shouldThrowOnBegin = error
    }

    func setShouldThrowOnRefresh(_ error: AuthError?) {
        self.shouldThrowOnRefresh = error
    }

    func beginLogin() async throws -> any LoginSession {
        if let error = shouldThrowOnBegin {
            throw error
        }
        guard let session = nextSession else {
            throw AuthError.unknown
        }
        return session
    }

    func refresh(credentials: Credentials) async throws -> Credentials {
        if let error = shouldThrowOnRefresh {
            throw error
        }
        guard let creds = nextCredentials else {
            throw AuthError.unknown
        }
        return creds
    }
}

struct MockLoginSession: LoginSession {
    let providerId: String
    let authURL: URL
    var resultCredentials: Credentials?
    var shouldThrow: AuthError?

    init(
        providerId: String = "mock",
        authURL: URL,
        credentials: Credentials? = nil,
        error: AuthError? = nil
    ) {
        self.providerId = providerId
        self.authURL = authURL
        self.resultCredentials = credentials
        self.shouldThrow = error
    }

    func complete(with callbackURL: URL) async throws -> Credentials {
        if let error = shouldThrow {
            throw error
        }
        guard let creds = resultCredentials else {
            throw AuthError.unknown
        }
        return creds
    }
}
