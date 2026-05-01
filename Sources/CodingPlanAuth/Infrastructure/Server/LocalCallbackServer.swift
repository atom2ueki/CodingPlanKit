// LocalCallbackServer.swift
// CodingPlanAuth

import Darwin
import Foundation
import SwiftWebServer

struct CallbackParameters: Sendable, Equatable {
    let code: String
    let state: String?

    init(code: String, state: String? = nil) {
        self.code = code
        self.state = state
    }
}

actor LocalCallbackServer {
    private static let ephemeralPortStartupAttempts = 5

    nonisolated let port: UInt16
    nonisolated let callbackPath: String

    // Configuration is immutable after init and read from the @MainActor
    // helper that constructs the SwiftWebServer instance, so it lives
    // outside the actor's isolation.
    nonisolated private let responseHTML: String
    nonisolated private let redirectBaseURL: String?
    /// When set, requests whose `state` query parameter doesn't match this
    /// value are rejected with HTTP 400 *without* consuming the single-shot
    /// resume. The legitimate browser callback (which carries the genuine
    /// state) can still arrive afterwards and complete the flow.
    /// State is OAuth's CSRF token (RFC 6749 §10.12) and is unguessable to
    /// any off-path attacker.
    nonisolated private let expectedState: String?
    private var server: SwiftWebServer?
    private var startedPort: UInt16?
    private var startupError: AuthError?
    private var continuation: CheckedContinuation<CallbackParameters, any Error>?
    private var startupContinuation: CheckedContinuation<UInt16, any Error>?

    init(
        port: UInt16 = 0,
        callbackPath: String = "/auth/callback",
        responseHTML: String? = nil,
        redirectBaseURL: String? = nil,
        expectedState: String? = nil
    ) {
        self.port = port
        self.callbackPath = callbackPath
        self.responseHTML = responseHTML ?? LocalCallbackServer.defaultSuccessHTML()
        self.redirectBaseURL = redirectBaseURL
        self.expectedState = expectedState
    }

    func start() async throws -> CallbackParameters {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Task { await self.startListening() }
        }
    }

    func waitUntilStarted() async throws -> UInt16 {
        if let startedPort {
            return startedPort
        }
        if let startupError {
            throw startupError
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.startupContinuation = continuation
        }
    }

    func stop() async {
        let currentServer = server
        continuation?.resume(throwing: AuthError.cancelled)
        continuation = nil
        startupContinuation?.resume(throwing: AuthError.cancelled)
        startupContinuation = nil
        server = nil
        startedPort = nil
        startupError = nil
        if let currentServer {
            await MainActor.run {
                currentServer.close()
            }
        }
    }

    var actualPort: UInt16? {
        startedPort
    }

    private enum StartupResult: Sendable {
        case success(UInt16)
        case failure(AuthError)
        case pending
    }

    private static func startupResult(from status: ServerStatus) -> StartupResult {
        switch status {
        case .running(let p) where p > 0 && p <= UInt(UInt16.max):
            return .success(UInt16(p))
        case .running(let p):
            return .failure(.callbackServerError("Callback server reported invalid port \(p)"))
        case .error(let message):
            return .failure(.callbackServerError(message))
        case .stopped:
            return .failure(.callbackServerError("Callback server stopped before it started"))
        case .starting:
            return .pending
        }
    }

    private func startListening() async {
        let shouldResolveEphemeralPort = port == 0
        let maxAttempts = shouldResolveEphemeralPort ? Self.ephemeralPortStartupAttempts : 1

        for attempt in 1...maxAttempts {
            guard continuation != nil else { return }

            let listenPort: UInt16
            do {
                listenPort = try Self.resolveListenPort(port)
            } catch {
                let authError = error as? AuthError ?? .callbackServerError(error.localizedDescription)
                finishStartup(with: .failure(authError))
                return
            }

            let server = await makeServer()
            self.server = server

            let result = await MainActor.run {
                // Bind to loopback only (RFC 8252 §7.3). "localhost" gives us
                // dual-stack 127.0.0.1 + ::1 in one call so the system browser
                // can reach the callback regardless of which family it picks.
                server.listen(UInt(listenPort), host: "localhost") { }
                return Self.startupResult(from: server.status)
            }

            if case .failure(let error) = result,
               shouldResolveEphemeralPort,
               attempt < maxAttempts,
               Self.isResolvedPortBindFailure(error) {
                self.server = nil
                await MainActor.run {
                    server.close()
                }
                continue
            }

            finishStartup(with: result)
            return
        }
    }

    @MainActor
    private func makeServer() -> SwiftWebServer {
        let server = SwiftWebServer()

        // Capture state into local constants so the route handler closure
        // doesn't synchronously reach into the actor's isolated storage.
        // (These properties are `nonisolated` immutable lets, so the read
        // is fine from the @MainActor context; capturing locally still
        // makes the closure's intent explicit.)
        let redirectBaseURL = self.redirectBaseURL
        let responseHTML = self.responseHTML
        let expectedState = self.expectedState

        // The closure is registered on @MainActor (server.get) but invoked on
        // SwiftWebServer's per-connection background dispatch queue. Mark it
        // @Sendable so its inferred isolation is non-isolated; without this
        // the runtime traps with "BUG IN CLIENT OF libdispatch" on the first
        // request because the closure inherits @MainActor from the call site.
        server.get(callbackPath) { @Sendable [weak self] request, response in
            let query = request.queryParameters
            guard let code = query["code"] else {
                response.status(.badRequest, error: "Missing authorization code")
                return
            }
            // Defense in depth: when we know the expected state, refuse
            // to fire the resume on a mismatch. A LAN-side forged
            // callback can no longer kill the legitimate browser one.
            if let expectedState, query["state"] != expectedState {
                response.status(.badRequest, error: "Invalid state")
                return
            }
            let params = CallbackParameters(code: code, state: query["state"])

            if let redirectBaseURL {
                var components = URLComponents(string: redirectBaseURL)
                var items = components?.queryItems ?? []
                items.append(URLQueryItem(name: "code", value: code))
                if let state = query["state"] {
                    items.append(URLQueryItem(name: "state", value: state))
                }
                components?.queryItems = items
                response.redirectTemporary(components?.string ?? redirectBaseURL)
            } else {
                response.status(.ok)
                response.header(.contentType, "text/html; charset=utf-8")
                response.send(responseHTML)
            }

            let target = self
            Task { await target?.resume(with: params) }
        }

        return server
    }

    private static func isResolvedPortBindFailure(_ error: AuthError) -> Bool {
        guard case .callbackServerError(let message) = error else { return false }
        // Either family can lose the race after `resolveListenPort`'s
        // reservation closed — match both so the retry loop fires.
        return message.hasPrefix("Failed to bind IPv4 socket on port ") ||
            message.hasPrefix("Failed to bind IPv6 socket on port ")
    }

    private static func resolveListenPort(_ port: UInt16) throws -> UInt16 {
        guard port == 0 else { return port }

        // SwiftWebServer reports `.running(port: 0)` for OS-assigned ports, so
        // reserve a candidate port first and retry startup if that race loses.
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw AuthError.callbackServerError("Could not create socket to reserve callback port")
        }
        defer { close(socketDescriptor) }

        var reuseAddress = 1
        guard setsockopt(
            socketDescriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout.size(ofValue: reuseAddress))
        ) == 0 else {
            throw AuthError.callbackServerError("Could not configure callback port socket")
        }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = INADDR_ANY
        address.sin_port = 0

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw AuthError.callbackServerError("Could not reserve callback port")
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketDescriptor, $0, &length)
            }
        }
        guard nameResult == 0 else {
            throw AuthError.callbackServerError("Could not read reserved callback port")
        }

        let reservedPort = UInt16(bigEndian: address.sin_port)
        guard reservedPort > 0 else {
            throw AuthError.callbackServerError("Reserved callback port was invalid")
        }
        return reservedPort
    }

    private func finishStartup(with result: StartupResult) {
        switch result {
        case .success(let port):
            startedPort = port
            guard let cont = startupContinuation else { return }
            startupContinuation = nil
            cont.resume(returning: port)
        case .failure(let error):
            let currentServer = server
            let startupCont = startupContinuation
            startupError = error
            startupContinuation = nil
            continuation?.resume(throwing: error)
            continuation = nil
            server = nil
            startedPort = nil
            if let currentServer {
                Task { @MainActor in
                    currentServer.close()
                }
            }
            startupCont?.resume(throwing: error)
        case .pending:
            break
        }
    }

    private func resume(with params: CallbackParameters) async {
        guard let cont = continuation else { return }
        let currentServer = server
        continuation = nil
        startupContinuation?.resume(throwing: AuthError.cancelled)
        startupContinuation = nil
        server = nil
        startedPort = nil
        startupError = nil
        if let currentServer {
            await MainActor.run {
                currentServer.close()
            }
        }
        cont.resume(returning: params)
    }

    private static func defaultSuccessHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Authentication Successful</title>
            <style>
                body { font-family: -apple-system, sans-serif; text-align: center; padding: 40px; background: #111; color: #eee; }
                h1 { color: #10a37f; }
            </style>
        </head>
        <body>
            <h1>Authentication Successful</h1>
            <p>You can close this window and return to the app.</p>
        </body>
        </html>
        """
    }
}
