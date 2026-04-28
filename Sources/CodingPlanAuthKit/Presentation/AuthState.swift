// AuthState.swift
// CodingPlanAuthKit

import Foundation
import Observation

/// SwiftUI-friendly façade over ``AuthService`` for a single provider.
///
/// Owned by your view layer (`@State` on a view, or stored on a view model).
/// Updates published via `@Observable` so SwiftUI tracks them automatically:
///
/// ```swift
/// @State private var authState = AuthState(service: service, providerId: "openai")
///
/// var body: some View {
///     if authState.isAuthenticated { … } else { signInButton }
/// }
/// ```
@Observable
@MainActor
public final class AuthState {
    /// `true` while a login, status check, or refresh is in flight.
    public private(set) var isLoading = false

    /// `true` once valid credentials are loaded for ``providerId``.
    public private(set) var isAuthenticated = false

    /// The currently-loaded credentials, or `nil` when signed out.
    public private(set) var currentCredentials: Credentials?

    /// The most recent error to surface in UI; cleared on the next success.
    public private(set) var lastError: AuthError?

    private let service: AuthService
    private let providerId: String

    /// Create a new state object scoped to a single provider id.
    /// - Parameters:
    ///   - service: The shared ``AuthService`` instance.
    ///   - providerId: The provider this state observes (e.g. `"openai"`).
    public init(
        service: AuthService,
        providerId: String
    ) {
        self.service = service
        self.providerId = providerId
    }

    /// Check current authentication status and update observable state.
    public func checkStatus() async {
        do {
            let creds = try await service.credentials(for: providerId)
            await update(credentials: creds)
        } catch {
            await setError(error)
        }
    }

    /// Begin login, returning the browser URL that must be presented.
    public func beginLogin() async throws -> any LoginSession {
        isLoading = true
        defer { isLoading = false }
        return try await service.beginLogin(providerId: providerId)
    }

    /// Complete login after the browser redirect.
    public func completeLogin(session: any LoginSession, callbackURL: URL) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let creds = try await service.completeLogin(
                session: session,
                with: callbackURL
            )
            await update(credentials: creds)
        } catch {
            await setError(error)
        }
    }

    /// Log out and clear observable state.
    public func logout() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await service.logout(providerId: providerId)
            await update(credentials: nil)
        } catch {
            await setError(error)
        }
    }

    // MARK: - Private

    private func update(credentials: Credentials?) async {
        self.currentCredentials = credentials
        self.isAuthenticated = credentials != nil
        self.lastError = nil
    }

    private func setError(_ error: any Error) async {
        if let authError = error as? AuthError {
            self.lastError = authError
        } else {
            self.lastError = AuthError.unknown
        }
    }
}
