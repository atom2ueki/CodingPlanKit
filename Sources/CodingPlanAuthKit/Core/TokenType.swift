// TokenType.swift
// CodingPlanAuthKit

import Foundation

/// The OAuth token scheme used in the `Authorization` header.
///
/// Almost always ``bearer``. Defined as a `RawRepresentable` struct rather
/// than an enum so unknown providers can round-trip arbitrary values without
/// becoming a breaking change.
public struct TokenType: RawRepresentable, Sendable, Equatable, Hashable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    /// The standard OAuth 2.0 bearer token scheme (RFC 6750).
    public static let bearer = TokenType(rawValue: "Bearer")
}
