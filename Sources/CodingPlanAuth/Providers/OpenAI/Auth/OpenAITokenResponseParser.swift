// OpenAITokenResponseParser.swift
// CodingPlanAuth
//
// OpenAI's flavor of ``OAuth2TokenResponseParser``: decodes the standard
// token-endpoint JSON and pulls `chatgpt_account_id`, `chatgpt_plan_type`,
// and the user's email out of the access / id token JWT claims.

import Foundation

/// ``OAuth2TokenResponseParser`` for OpenAI / ChatGPT.
public struct OpenAITokenResponseParser: OAuth2TokenResponseParser {
    public init() {}

    public func parse(_ data: Data, fallbackRefreshToken: String?) throws -> Credentials {
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
            let token_type: String?
            let id_token: String?
        }

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresAt = Self.expirationDate(
            expiresIn: decoded.expires_in,
            accessToken: decoded.access_token,
            idToken: decoded.id_token
        )

        let accessPayload = Self.jwtPayload(from: decoded.access_token)
        let idPayload = decoded.id_token.flatMap { Self.jwtPayload(from: $0) }
        let payloads = [accessPayload, idPayload]
        let accountId = Self.authClaim("chatgpt_account_id", in: payloads)
        let accountPlanType = Self.authClaim("chatgpt_plan_type", in: payloads)
        let accountEmail = Self.email(in: payloads)

        return Credentials(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? fallbackRefreshToken,
            idToken: decoded.id_token,
            expiresAt: expiresAt,
            tokenType: decoded.token_type.map(TokenType.init(rawValue:)) ?? .bearer,
            accountId: accountId,
            accountEmail: accountEmail,
            accountPlanType: accountPlanType
        )
    }

    static func jwtPayload(from token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func expirationDate(expiresIn: Int?, accessToken: String, idToken: String?) -> Date? {
        if let expiresIn {
            return Date().addingTimeInterval(TimeInterval(expiresIn))
        }
        let payloads = [
            jwtPayload(from: accessToken),
            idToken.flatMap { jwtPayload(from: $0) },
        ]
        for payload in payloads {
            if let timestamp = unixTimestamp(payload?["exp"]) {
                return Date(timeIntervalSince1970: timestamp)
            }
        }
        return nil
    }

    private static func unixTimestamp(_ value: Any?) -> TimeInterval? {
        switch value {
        case let number as NSNumber:
            number.doubleValue
        case let string as String:
            Double(string)
        default:
            nil
        }
    }

    private static func authClaim(_ key: String, in payloads: [[String: Any]?]) -> String? {
        for payload in payloads {
            guard let auth = payload?["https://api.openai.com/auth"] as? [String: Any],
                  let value = auth[key] as? String else {
                continue
            }
            return value
        }
        return nil
    }

    private static func email(in payloads: [[String: Any]?]) -> String? {
        for payload in payloads {
            if let email = payload?["email"] as? String {
                return email
            }
            if let profile = payload?["https://api.openai.com/profile"] as? [String: Any],
               let email = profile["email"] as? String {
                return email
            }
        }
        return nil
    }
}
