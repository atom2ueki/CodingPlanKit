// HTTPClient.swift
// CodingPlanAuthKit

import Foundation

/// HTTP method.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// A request to send via an ``HTTPClient``.
public struct HTTPRequest: Sendable {
    public let url: URL
    public let method: HTTPMethod
    public let headers: [String: String]
    public let body: Data?

    public init(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

/// The response returned by an ``HTTPClient``.
public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    /// `true` when the status code is in the 2xx range.
    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

/// A streaming response: status + headers eagerly available, body as a
/// chunked async sequence.
public struct HTTPStreamingResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: AsyncThrowingStream<Data, any Error>

    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    public init(
        statusCode: Int,
        headers: [String: String] = [:],
        body: AsyncThrowingStream<Data, any Error>
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

/// An abstraction over HTTP networking for testability.
public protocol HTTPClient: Sendable {
    /// Perform an HTTP request and return the buffered response.
    func send(_ request: HTTPRequest) async throws -> HTTPResponse

    /// Perform an HTTP request and return a streaming response.
    /// Default implementation throws — only transports backed by
    /// `URLSession.bytes(for:)` (or equivalent) need to override this.
    func sendStreaming(_ request: HTTPRequest) async throws -> HTTPStreamingResponse
}

public extension HTTPClient {
    func sendStreaming(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        throw AuthError.networkError("This HTTPClient does not support streaming.")
    }
}

/// A concrete ``HTTPClient`` backed by `URLSession`.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let urlRequest = Self.makeURLRequest(from: request)
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        return HTTPResponse(
            statusCode: httpResponse.statusCode,
            headers: Self.headers(from: httpResponse),
            body: data
        )
    }

    public func sendStreaming(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        let urlRequest = Self.makeURLRequest(from: request)
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        let stream = AsyncThrowingStream<Data, any Error> { continuation in
            let task = Task {
                do {
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 1024 {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty { continuation.yield(buffer) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        return HTTPStreamingResponse(
            statusCode: httpResponse.statusCode,
            headers: Self.headers(from: httpResponse),
            body: stream
        )
    }

    private static func makeURLRequest(from request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        return urlRequest
    }

    private static func headers(from response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headers[k] = v
            }
        }
        return headers
    }
}
