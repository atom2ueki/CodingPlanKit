import CryptoKit
import Foundation
import Testing
@testable import CodingPlanAuth

struct PKCETests {
    @Test
    func generatedVerifierMeetsPKCELengthAndCharacterRules() {
        let pkce = PKCE.generate()
        #expect(pkce.method == "S256")
        #expect((43...128).contains(pkce.verifier.count))
        #expect(pkce.challenge.count == 43)
        #expect(pkce.verifier.range(of: "[^A-Za-z0-9._~-]", options: .regularExpression) == nil)
        #expect(pkce.challenge.range(of: "[^A-Za-z0-9_-]", options: .regularExpression) == nil)
    }

    @Test
    func challengeIsBase64URLEncodedSHA256OfVerifier() {
        // RFC 7636 §4.2 — for `code_challenge_method=S256`, the challenge MUST
        // be `BASE64URL(SHA256(ASCII(verifier)))`. If this drifts, the OpenAI
        // token endpoint rejects the auth-code exchange with `invalid_grant`.
        let pkce = PKCE.generate()
        let expected = Data(SHA256.hash(data: Data(pkce.verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(pkce.challenge == expected)
    }
}
