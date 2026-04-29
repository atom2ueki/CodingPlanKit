// OAuth2TokenResponseParser.swift
// CodingPlanAuth

import Foundation

/// A provider-specific parser for the JSON body of an OAuth 2.0 token
/// response (`https://tools.ietf.org/html/rfc6749#section-5.1`).
///
/// The shape of the wire response is standard, but providers embed their
/// own claims (account id, plan type, email) inside JWT payloads. Each
/// provider implements one of these to decode `Credentials` correctly.
public protocol OAuth2TokenResponseParser: Sendable {
    /// Decode `data` (the raw response body) into ``Credentials``.
    ///
    /// - Parameter fallbackRefreshToken: Used when the response omits a
    ///   `refresh_token` (common on refresh-grant responses) so the existing
    ///   refresh token isn't lost.
    func parse(_ data: Data, fallbackRefreshToken: String?) throws -> Credentials
}
