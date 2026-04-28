import Foundation
import Testing
@testable import CodingPlanAuthKit

struct PKCETests {
    @Test
    func generatedPKCEHasVerifierAndChallenge() {
        let pkce = PKCE.generate()
        #expect(!pkce.verifier.isEmpty)
        #expect(!pkce.challenge.isEmpty)
        #expect(pkce.method == "S256")
    }

    @Test
    func generatedVerifierMeetsPKCELengthAndCharacterRules() {
        let pkce = PKCE.generate()
        #expect((43...128).contains(pkce.verifier.count))
        #expect(pkce.challenge.count == 43)
        #expect(pkce.verifier.range(of: "[^A-Za-z0-9._~-]", options: .regularExpression) == nil)
        #expect(pkce.challenge.range(of: "[^A-Za-z0-9_-]", options: .regularExpression) == nil)
    }

    @Test
    func verifierAndChallengeAreDifferent() {
        let pkce = PKCE.generate()
        #expect(pkce.verifier != pkce.challenge)
    }

    @Test
    func eachGenerationIsUnique() {
        let a = PKCE.generate()
        let b = PKCE.generate()
        #expect(a.verifier != b.verifier)
        #expect(a.challenge != b.challenge)
    }
}
