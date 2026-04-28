// OAuth2Helpers.swift
// CodingPlanAuthKit
//
// Provider-agnostic helpers used internally by OAuth2PKCEFlow and any
// provider that wants to build OAuth requests by hand.

import Foundation

/// Generate a random `state` value for OAuth 2.0 CSRF protection.
func randomState(length: Int = 32) -> String {
    let alphabet: [Character] = Array(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )
    var rng = SystemRandomNumberGenerator()
    return String((0..<length).map { _ in
        alphabet[Int.random(in: 0..<alphabet.count, using: &rng)]
    })
}

/// Encode `params` as `application/x-www-form-urlencoded`, per RFC 6749 §4.1.3.
func formURLEncoded(_ params: [String: String]) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")

    return params.map { key, value in
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
        let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return "\(encodedKey)=\(encodedValue)"
    }.joined(separator: "&")
}
