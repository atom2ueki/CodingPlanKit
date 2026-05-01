import Foundation
import Darwin
import Testing
@testable import CodingPlanAuth

struct LocalCallbackServerTests {
    @Test
    func portZeroStartsOnResolvedPort() async throws {
        let server = LocalCallbackServer(port: 0, callbackPath: "/auth/callback")
        let task = Task { try await server.start() }

        let actualPort = try await server.waitUntilStarted()
        #expect(actualPort > 0)

        await server.stop()
        _ = try? await task.value
    }

    @Test
    func reportsBindFailureDuringStartup() async throws {
        let reservation = try reserveLocalPort()
        defer { close(reservation.socket) }

        let server = LocalCallbackServer(port: reservation.port, callbackPath: "/auth/callback")
        let task = Task { try await server.start() }

        do {
            _ = try await server.waitUntilStarted()
            await server.stop()
            #expect(Bool(false), "Expected callback server startup to fail")
        } catch {
            guard case .callbackServerError = error as? AuthError else {
                throw error
            }
        }

        _ = try? await task.value
    }

    // MARK: - Defense-in-depth: state validation at the callback handler

    /// A correct `state` plus `code` finishes the flow normally.
    @Test
    func callbackWithMatchingStateCompletesFlow() async throws {
        let server = LocalCallbackServer(
            port: 0,
            callbackPath: "/auth/callback",
            expectedState: "the-real-state"
        )
        let serverTask = Task { try await server.start() }
        let port = try await server.waitUntilStarted()

        let (status, _) = try await callbackGET(
            port: port,
            query: "code=abc&state=the-real-state"
        )
        #expect(status == 200)

        let params = try await serverTask.value
        #expect(params.code == "abc")
        #expect(params.state == "the-real-state")
    }

    /// A request with the wrong `state` MUST return 400 and MUST NOT
    /// burn the single-shot resume — the legitimate browser callback
    /// (which carries the genuine state) needs to still win.
    @Test
    func callbackWithMismatchedStateRejectsAndKeepsResumeAlive() async throws {
        let server = LocalCallbackServer(
            port: 0,
            callbackPath: "/auth/callback",
            expectedState: "the-real-state"
        )
        let serverTask = Task { try await server.start() }
        let port = try await server.waitUntilStarted()

        // 1) Forged callback with the wrong state — server rejects.
        let (badStatus, _) = try await callbackGET(
            port: port,
            query: "code=stolen&state=attacker-state"
        )
        #expect(badStatus == 400)

        // 2) The server has not yet resumed; the genuine browser
        //    callback can still complete the flow.
        let (goodStatus, _) = try await callbackGET(
            port: port,
            query: "code=genuine&state=the-real-state"
        )
        #expect(goodStatus == 200)

        let params = try await serverTask.value
        #expect(params.code == "genuine", "Genuine callback must win, not the forged one")
        #expect(params.state == "the-real-state")
    }

    /// A request with no `state` at all MUST also be rejected when the
    /// server is configured with an `expectedState`.
    @Test
    func callbackWithMissingStateRejectsWhenExpectedStateSet() async throws {
        let server = LocalCallbackServer(
            port: 0,
            callbackPath: "/auth/callback",
            expectedState: "the-real-state"
        )
        let serverTask = Task { try await server.start() }
        let port = try await server.waitUntilStarted()

        let (status, _) = try await callbackGET(port: port, query: "code=abc")
        #expect(status == 400)

        // Cleanup: cancel the still-pending start() so the test exits.
        await server.stop()
        _ = try? await serverTask.value
    }

    /// When the server isn't configured with an `expectedState`, the
    /// state check is skipped entirely (back-compat with callers that
    /// haven't migrated). A request with whatever state still completes.
    @Test
    func callbackWithoutExpectedStateAcceptsAnyState() async throws {
        let server = LocalCallbackServer(port: 0, callbackPath: "/auth/callback")
        let serverTask = Task { try await server.start() }
        let port = try await server.waitUntilStarted()

        let (status, _) = try await callbackGET(
            port: port,
            query: "code=abc&state=anything"
        )
        #expect(status == 200)

        let params = try await serverTask.value
        #expect(params.code == "abc")
        #expect(params.state == "anything")
    }

    private func callbackGET(port: UInt16, query: String) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/auth/callback?\(query)")!)
        request.httpMethod = "GET"
        // Don't follow redirects — the redirect path is exercised
        // separately and would obscure the status code we want here.
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.callbackServerError("Non-HTTP response from callback server")
        }
        return (http.statusCode, data)
    }

    private func reserveLocalPort() throws -> (socket: Int32, port: UInt16) {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw AuthError.callbackServerError("Could not create test socket")
        }

        // Bind to loopback (not INADDR_ANY) so we conflict with the
        // server-under-test which also binds loopback. With SO_REUSEADDR,
        // an INADDR_ANY reservation does not prevent a more-specific
        // loopback bind at the same port — the test would no longer
        // observe a real port conflict.
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        address.sin_port = 0

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(socketDescriptor)
            throw AuthError.callbackServerError("Could not bind test socket")
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketDescriptor, $0, &length)
            }
        }
        guard nameResult == 0 else {
            close(socketDescriptor)
            throw AuthError.callbackServerError("Could not read test socket port")
        }

        guard listen(socketDescriptor, 1) == 0 else {
            close(socketDescriptor)
            throw AuthError.callbackServerError("Could not listen on test socket")
        }

        return (socketDescriptor, UInt16(bigEndian: address.sin_port))
    }
}
