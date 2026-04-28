// PKCE.swift
// CodingPlanAuthKit

import CryptoKit
import Foundation

/// PKCE (Proof Key for Code Exchange) parameters for OAuth flows.
public struct PKCE: Sendable, Equatable {
    public let verifier: String
    public let challenge: String
    public let method: String

    public init(verifier: String, challenge: String, method: String = "S256") {
        self.verifier = verifier
        self.challenge = challenge
        self.method = method
    }

    /// Generate a new PKCE pair using a random verifier that stays inside the
    /// OAuth PKCE 43-128 character limit after base64url encoding.
    public static func generate() -> PKCE {
        let verifier = Data((0..<64).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
        let challenge = challengeData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        return PKCE(verifier: verifier, challenge: challenge, method: "S256")
    }
}
