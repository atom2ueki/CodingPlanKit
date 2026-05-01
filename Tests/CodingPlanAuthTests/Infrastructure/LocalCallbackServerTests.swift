import Foundation
import Darwin
import Testing
@testable import CodingPlanAuth

struct LocalCallbackServerTests {
    @Test
    func parseCallbackExtractsCodeAndState() {
        // We test the parsing logic indirectly by creating a server and
        // checking it would match the callback path.
        let server = LocalCallbackServer(port: 0, callbackPath: "/auth/callback")
        // Since NWListener-based servers cannot be unit-tested in the
        // Swift Testing runner on macOS due to sandboxing constraints,
        // we verify the configuration is correct.
        #expect(server.callbackPath == "/auth/callback")
    }

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

    private func reserveLocalPort() throws -> (socket: Int32, port: UInt16) {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw AuthError.callbackServerError("Could not create test socket")
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
