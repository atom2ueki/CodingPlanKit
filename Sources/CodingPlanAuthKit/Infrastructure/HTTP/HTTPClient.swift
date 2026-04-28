// HTTPClient.swift
// CodingPlanAuthKit

import Foundation

/// An abstraction over HTTP networking for testability.
public protocol HTTPClient: Sendable {
    /// Perform an HTTP request and return the response body and metadata.
    func request(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?
    ) async throws -> (data: Data, response: HTTPURLResponse)
}

/// A concrete ``HTTPClient`` backed by `URLSession`.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func request(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        return (data, httpResponse)
    }
}
