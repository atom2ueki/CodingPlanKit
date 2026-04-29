// LocalCallbackServer.swift
// CodingPlanAuthKit

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

private final class WebServerBox: @unchecked Sendable {
    // Reason: SwiftWebServer 0.1.0 does not yet declare itself Sendable.
    // The instance is only ever touched from MainActor below.
    let server: SwiftWebServer

    init(_ server: SwiftWebServer) {
        self.server = server
    }
}

actor LocalCallbackServer {
    nonisolated let port: UInt16
    nonisolated let callbackPath: String

    private let responseHTML: String
    private let redirectBaseURL: String?
    private var server: WebServerBox?
    private var startedPort: UInt16?
    private var startupError: AuthError?
    private var continuation: CheckedContinuation<CallbackParameters, any Error>?
    private var startupContinuation: CheckedContinuation<UInt16, any Error>?

    init(
        port: UInt16 = 0,
        callbackPath: String = "/auth/callback",
        responseHTML: String? = nil,
        redirectBaseURL: String? = nil
    ) {
        self.port = port
        self.callbackPath = callbackPath
        self.responseHTML = responseHTML ?? LocalCallbackServer.defaultSuccessHTML()
        self.redirectBaseURL = redirectBaseURL
    }

    func start() async throws -> CallbackParameters {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let server = WebServerBox(SwiftWebServer())
            self.server = server

            // Capture state into local constants so the handler closure doesn't
            // synchronously reach into the actor.
            let redirectBaseURL = self.redirectBaseURL
            let responseHTML = self.responseHTML

            server.server.get(callbackPath) { [weak self] request, response in
                let query = request.queryParameters
                guard let code = query["code"] else {
                    response.status(.badRequest, error: "Missing authorization code")
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

            let listenPort = self.port
            Task { @MainActor in
                server.server.listen(UInt(listenPort)) { }
                let result = Self.startupResult(from: server.server.status)
                Task { await self.finishStartup(with: result) }
            }
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
                currentServer.server.close()
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
                    currentServer.server.close()
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
                currentServer.server.close()
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
