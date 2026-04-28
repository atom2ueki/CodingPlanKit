import Foundation
@testable import CodingPlanAuthKit

struct RecordedHTTPRequest: Sendable, Equatable {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data?
}

actor MockHTTPClient: HTTPClient {
    var responses: [URL: (data: Data, statusCode: Int)] = [:]
    var requestedURLs: [URL] = []
    private var requests: [RecordedHTTPRequest] = []

    func setResponse(for url: URL, data: Data, statusCode: Int = 200) {
        responses[url] = (data, statusCode)
    }

    func recordedRequests() -> [RecordedHTTPRequest] {
        requests
    }

    func request(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        requestedURLs.append(url)
        requests.append(RecordedHTTPRequest(url: url, method: method, headers: headers, body: body))
        guard let stub = responses[url] else {
            throw AuthError.networkError("No stub for \(url)")
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (stub.data, response)
    }
}
