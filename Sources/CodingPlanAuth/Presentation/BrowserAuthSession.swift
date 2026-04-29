// BrowserAuthSession.swift
// CodingPlanAuth

#if canImport(AuthenticationServices)
import AuthenticationServices
import Foundation

/// A platform-specific helper that uses `ASWebAuthenticationSession` to present
/// the OAuth URL and return the callback URL.
///
/// This is the smoothest UX on iOS / macOS because it shares cookies with
/// Safari and automatically dismisses when the callback is intercepted.
@MainActor
public final class BrowserAuthSession: NSObject {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, any Error>?

    public override init() {
        super.init()
    }

    /// Present the OAuth URL and wait for the callback.
    ///
    /// - Parameters:
    ///   - url: The authorization URL from ``LoginSession.authURL``.
    ///   - callbackScheme: The URL scheme that should trigger dismissal.
    ///     For localhost callbacks bridged through a custom scheme, pass that
    ///     scheme (e.g. `"codingplanauthkit"`). For direct `http` callbacks
    ///     use `"http"`.
    /// - Returns: The callback URL.
    public func authenticate(
        url: URL,
        callbackScheme: String
    ) async throws -> URL {
        guard session == nil, continuation == nil else {
            throw AuthError.browserPresentationFailed("A browser authentication session is already active.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.finish(callbackURL: callbackURL, error: error)
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            #if os(iOS)
            session.presentationContextProvider = self
            #elseif os(macOS)
            session.presentationContextProvider = self
            #endif
            self.session = session
            if !session.start() {
                finish(
                    callbackURL: nil,
                    error: AuthError.browserPresentationFailed("The system refused to start the browser authentication session.")
                )
            }
        }
    }

    private func finish(callbackURL: URL?, error: (any Error)?) {
        guard let continuation else { return }
        self.continuation = nil
        session = nil

        if let error {
            if let authError = error as? AuthError {
                continuation.resume(throwing: authError)
            } else if let sessionError = error as? ASWebAuthenticationSessionError,
                      sessionError.code == .canceledLogin {
                continuation.resume(throwing: AuthError.cancelled)
            } else {
                continuation.resume(throwing: AuthError.browserPresentationFailed(error.localizedDescription))
            }
        } else if let callbackURL {
            continuation.resume(returning: callbackURL)
        } else {
            continuation.resume(throwing: AuthError.unknown)
        }
    }
}

#if os(iOS)
extension BrowserAuthSession: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.windows.first { $0.isKeyWindow } ?? UIWindow()
    }
}
#elseif os(macOS)
extension BrowserAuthSession: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
#endif
#endif
