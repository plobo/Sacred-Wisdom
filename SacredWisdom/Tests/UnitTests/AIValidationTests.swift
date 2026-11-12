import Foundation
import Testing
@testable import SacredWisdom

/// Real passage texts (as in the bundled library) so quotation checks run on genuine scripture.
private enum AIFixtures {
    static let kjv = Translation(id: "bible-kjv", collectionID: "bible", name: "King James Version", languageCode: "en",
                                 translator: "", year: 1769, source: Fixtures.source)
    static let sujato = Translation(id: "dhp-sujato", collectionID: "tripitaka", name: "Bhikkhu Sujato", languageCode: "en",
                                    translator: "", year: 2021, source: Fixtures.source)

    static let matthew59 = ScripturePassage(
        id: "bible.matthew.5.9", religionID: "christianity", collectionID: "bible", bookID: "b", sectionID: "s", sequence: 9,
        reference: "Matthew 5:9", originalLanguage: "en", originalText: nil, originalSource: nil,
        texts: [PassageText(translation: kjv, text: "Blessed are the peacemakers: for they shall be called the children of God.")]
    )
    static let dhammapada5 = ScripturePassage(
        id: "dhammapada.5", religionID: "buddhism", collectionID: "tripitaka", bookID: "b", sectionID: "s", sequence: 5,
        reference: "Dhammapada 5", originalLanguage: "pi", originalText: nil, originalSource: nil,
        texts: [PassageText(translation: sujato, text: "For never is hatred\nlaid to rest by hate,\nit’s laid to rest by love:\nthis is an ancient teaching.")]
    )
    static let passages = [matthew59, dhammapada5]

    static func response(_ text: String, cited: [Int] = []) -> ScriptureAIResponse {
        ScriptureAIResponse(explanation: text, citedPassageNumbers: cited, providerName: "Test")
    }
}

@Suite struct AIResponseValidatorTests {
    private func validate(_ text: String, cited: [Int] = []) -> Result<ValidatedExplanation, AIResponseValidator.Rejection> {
        AIResponseValidator.validate(AIFixtures.response(text, cited: cited), passages: AIFixtures.passages)
    }

    @Test func keepsGroundedExplanationAndMapsCitations() throws {
        let result = try validate("Matthew 5:9 blesses those who make peace [1]. The Dhammapada says hatred ends through love [2].").get()
        #expect(result.removedSentenceCount == 0)
        #expect(result.citations.map(\.reference) == ["Matthew 5:9", "Dhammapada 5"])
        #expect(result.citations.map(\.passageID) == ["bible.matthew.5.9", "dhammapada.5"])
    }

    @Test func removesSentenceWithFabricatedQuotation() throws {
        let result = try validate("Peace is praised [1]. Jesus said “peace be with all nations” [1]. Hatred ends with love [2].").get()
        #expect(result.removedSentenceCount == 1)
        #expect(!result.text.contains("all nations"))
        #expect(result.text == "Peace is praised [1]. Hatred ends with love [2].")
    }

    @Test func keepsVerbatimQuotationIgnoringCaseAndPunctuation() throws {
        // Line breaks and punctuation inside the scripture don't matter; word order does.
        let result = try validate("The passage calls peacemakers “The Children of God” [1]. It says \"hatred, laid to rest by hate\" [2].").get()
        #expect(result.removedSentenceCount == 0)
        let reordered = try validate("Peace matters [1]. It says “hate laid to rest by hatred” [2].").get()
        #expect(reordered.removedSentenceCount == 1)
        let verbatim = try validate("It teaches that hatred is “laid to rest by love” [2].").get()
        #expect(verbatim.removedSentenceCount == 0)
    }

    @Test func removesSentencesCitingPassagesThatWereNotProvided() throws {
        let result = try validate("Peace is blessed [1]. Another text agrees [7].").get()
        #expect(result.removedSentenceCount == 1)
        #expect(result.citations.map(\.number) == [1])
    }

    @Test func removesSentencesNamingReferencesOutsideTheContext() throws {
        let result = try validate("Matthew 5:9 speaks of peacemakers [1]. John 3:16 speaks of love [1].").get()
        #expect(result.text == "Matthew 5:9 speaks of peacemakers [1].")
    }

    @Test func rejectsWhenNothingVerifiableRemains() {
        #expect(validate("As written in John 3:16 [1].") == .failure(.empty))
        #expect(validate("“All paths lead to the same summit” [1].") == .failure(.empty))
        #expect(AIResponseValidator.validate(AIFixtures.response("Peace [1]."), passages: []) == .failure(.empty))
    }

    @Test func rejectsExplanationThatCitesNothing() {
        #expect(validate("Both traditions value peace.") == .failure(.noValidCitations))
        #expect(validate("Both traditions value peace.", cited: [5, 0, -1]) == .failure(.noValidCitations))
    }

    @Test func structuredCitationsCountEvenWithoutInlineMarkers() throws {
        let result = try validate("Both passages speak of ending conflict.", cited: [2, 1, 2]).get()
        #expect(result.citations.map(\.number) == [1, 2])
    }

    @Test func capsLength() throws {
        let long = String(repeating: "Peace is a blessing in this passage [1]. ", count: 80)
        let result = try validate(long).get()
        #expect(result.text.count <= AIResponseValidator.maximumLength + 1)
    }

    @Test func parsesMarkersQuotesAndReferences() {
        #expect(AIResponseValidator.citationMarkers(in: "See [1] and [2, 3].") == [1, 2, 3])
        #expect(AIResponseValidator.quotedSpans(in: "It says “a b” and \"c d\"; it’s fine.") == ["a b", "c d"])
        #expect(AIResponseValidator.referenceMentions(in: "Compare 1 John 4:8, Bhagavad Gita 2.47 and Psalms 23:1.")
            == ["1 John 4:8", "Bhagavad Gita 2.47", "Psalms 23:1"])
    }
}

@Suite struct RemoteAIServiceTests {
    struct FakeProvider: RemoteAIProvider {
        var reply: String
        var isConfigured = true
        let name = "Fake online model"
        let received = Received()

        final class Received: @unchecked Sendable {
            var system = ""
            var user = ""
        }

        func complete(system: String, user: String) async throws(AppError) -> String {
            received.system = system
            received.user = user
            return reply
        }
    }

    @Test func buildsGroundedPromptAndParsesJSON() async throws {
        let provider = FakeProvider(reply: "Here you go:\n```json\n{\"explanation\": \"Peace [1].\", \"citedPassages\": [1]}\n```")
        let service = RemoteScriptureAIService(provider: provider, religions: try Fixtures.repository())
        let response = try await service.answer(question: "What about peace?", passages: AIFixtures.passages)
        #expect(response == ScriptureAIResponse(explanation: "Peace [1].", citedPassageNumbers: [1], providerName: "Fake online model"))
        #expect(provider.received.system.contains("Use only the numbered passages"))
        #expect(provider.received.user.contains("[1] Matthew 5:9"))
        #expect(provider.received.user.contains("[2] Dhammapada 5"))
        #expect(provider.received.user.hasPrefix("Question: What about peace?"))
    }

    @Test func unreadableReplyThrowsAndUnconfiguredIsUnavailable() async throws {
        #expect(throws: AppError.self) { try RemoteScriptureAIService.parse("no json here", providerName: "x") }
        let service = RemoteScriptureAIService(provider: FakeProvider(reply: "", isConfigured: false), religions: try Fixtures.repository())
        guard case .unavailable = await service.availability() else { Issue.record("should be unavailable"); return }
    }

    @Test func promptShortensLongPassagesAndCapsCount() {
        let long = ScripturePassage(
            id: "x", religionID: "r", collectionID: "c", bookID: "b", sectionID: "s", sequence: 1, reference: "REF",
            originalLanguage: "en", originalText: nil, originalSource: nil,
            texts: [PassageText(translation: AIFixtures.kjv, text: String(repeating: "a", count: 5_000))]
        )
        let prompt = ScriptureAIPrompt.prompt(question: "q", passages: [long], religionNames: [:])
        #expect(prompt.count < ScriptureAIPrompt.maximumCharactersPerPassage + 300)
        #expect(ScriptureAIPrompt.context(for: Array(repeating: long, count: 20)).count == ScriptureAIPrompt.maximumPassages)
    }
}
