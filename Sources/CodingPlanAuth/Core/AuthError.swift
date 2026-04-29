// AuthError.swift
// CodingPlanAuth

import Foundation

/// Errors that can occur during authentication flows.
public enum AuthError: Error, Sendable, Equatable {
    case invalidURL
    case invalidResponse
    case tokenExchangeFailed(statusCode: Int?, message: String)
    case invalidState
    case missingAuthorizationCode
    case cancelled
    case pkceGenerationFailed
    case storageError(String)
    case networkError(String)
    case unknown
    case notAuthenticated
    case unsupportedProvider
    case callbackServerError(String)
    case browserPresentationFailed(String)
}

extension AuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "The OAuth URL was malformed."
        case .invalidResponse: "The server returned an invalid response."
        case .tokenExchangeFailed(let status, let message):
            if let status {
                "Token exchange failed (\(status)): \(message)"
            } else {
                "Token exchange failed: \(message)"
            }
        case .invalidState: "OAuth state did not match — possible CSRF."
        case .missingAuthorizationCode: "The callback URL did not include an authorization code."
        case .cancelled: "Authentication was cancelled."
        case .pkceGenerationFailed: "Failed to generate the PKCE challenge."
        case .storageError(let message): "Credential storage error: \(message)"
        case .networkError(let message): "Network error: \(message)"
        case .unknown: "An unknown error occurred."
        case .notAuthenticated: "No valid credentials are available for this provider."
        case .unsupportedProvider: "No provider is registered for this identifier."
        case .callbackServerError(let message): "Local callback server error: \(message)"
        case .browserPresentationFailed(let message): "Browser presentation failed: \(message)"
        }
    }
}
