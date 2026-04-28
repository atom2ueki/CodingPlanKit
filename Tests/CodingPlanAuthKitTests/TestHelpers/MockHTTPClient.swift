import Foundation
@testable import CodingPlanAuthKit

struct RecordedHTTPRequest: Sendable, Equatable {
    let url: URL
    let method: HTTPMethod
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

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requestedURLs.append(request.url)
        requests.append(RecordedHTTPRequest(
            url: request.url,
            method: request.method,
            headers: request.headers,
            body: request.body
        ))
        guard let stub = responses[request.url] else {
            throw AuthError.networkError("No stub for \(request.url)")
        }
        return HTTPResponse(statusCode: stub.statusCode, body: stub.data)
    }
}
