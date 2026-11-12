import Foundation
import Testing
@testable import SacredWisdom

/// Siri / Shortcuts answers over the real bundled library.
@Suite struct ScriptureIntentIntegrationTests {
    private func makeService() async throws -> (ScriptureIntentService, SQLiteScriptureRepository) {
        let url = try #require(Bundle(for: AppDependencies.self)
            .url(forResource: SampleLibraryRepository.resourceName, withExtension: "json"))
        let database = DatabaseManager(location: .inMemory,
                                       bundledPackages: [.init(id: SampleLibraryRepository.resourceName, url: url)])
        let sqlite = SQLiteScriptureRepository(database: database)
        let search = SearchScriptureUseCase(
            search: LocalKeywordSearchRepository(index: FullTextSearchIndex(database: database), scripture: sqlite),
            religions: sqlite
        )
        return (ScriptureIntentService(search: search, scripture: sqlite), sqlite)
    }

    /// Every quotation in a spoken answer must be a complete, verbatim translation text from the database.
    private func expectOnlyVerbatimQuotes(_ response: IntentResponse) {
        for passage in response.passages.prefix(ScriptureIntentService.spokenLimit) {
            guard let text = passage.texts.first(where: { response.dialog.contains($0.text) }) else {
                Issue.record("\(passage.reference) is named but none of its texts is quoted verbatim")
                continue
            }
            #expect(response.dialog.contains("\(passage.reference): \(text.text)"))
        }
    }

    @Test func searchReturnsCorrectReferences() async throws {
        let (service, _) = try await makeService()
        let response = try await service.searchReferences("peacemakers")
        #expect(response.passages.map(\.reference) == ["Matthew 5:9"])
        #expect(response.dialog == "Found 1 passage in 1 tradition for “peacemakers”. Top matches: Matthew 5:9 (Christianity).")
    }

    @Test func searchAcrossTraditionsNamesOnePerTradition() async throws {
        let (service, _) = try await makeService()
        let response = try await service.searchReferences("merciful")
        #expect(Set(response.passages.map(\.reference)) == ["Matthew 5:7", "Al-Fatihah 1:1", "Al-Fatihah 1:3"])
        #expect(response.dialog.contains("(Christianity)"))
        #expect(response.dialog.contains("(Islam)"))
    }

    @Test func questionQuotesVerbatimPassagesFromSeveralTraditions() async throws {
        let (service, _) = try await makeService()
        let response = try await service.answer("What is said about the merciful?")
        #expect(response.dialog.hasPrefix("Passages from 2 traditions speak to this."))
        #expect(response.passages.count == 2)
        expectOnlyVerbatimQuotes(response)
    }

    @Test func hatredQuestionQuotesTheDhammapada() async throws {
        let (service, _) = try await makeService()
        let response = try await service.answer("How can hatred cease?")
        #expect(response.passages.first?.collectionID == "tripitaka")
        expectOnlyVerbatimQuotes(response)
    }

    @Test(arguments: ScriptureTopicQuery.allCases.filter { $0 != .forgiveness })
    func everyOfferedTopicFindsPassages(topic: ScriptureTopicQuery) async throws {
        let (service, _) = try await makeService()
        let response = try await service.answer(topic.query)
        #expect(!response.passages.isEmpty, "\(topic) finds nothing")
        expectOnlyVerbatimQuotes(response)
    }

    /// The spec's voice example. The sample library has no passage on forgiveness, and the answer says so
    /// rather than inventing one.
    @Test func forgivenessHonestlyReportsNoPassagesInSampleLibrary() async throws {
        let (service, _) = try await makeService()
        let response = try await service.answer("forgiveness")
        #expect(response.passages.isEmpty)
        #expect(response.dialog == "I couldn’t find passages about “forgiveness” in the installed library.")
    }

    @Test func emptyInputPromptsInsteadOfSearching() async throws {
        let (service, _) = try await makeService()
        #expect(try await service.searchReferences("  ").passages.isEmpty)
        #expect(try await service.answer("").dialog == "What would you like to ask?")
    }

    @Test func dailyPassageMatchesHomeAndIsQuotedVerbatim() async throws {
        let (service, repo) = try await makeService()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let response = try await service.dailyPassage(on: date)
        let expected = try #require(try await repo.dailyPassage(on: date))
        #expect(response.passages == [expected])
        let text = try #require(expected.texts.first)
        let collection = try await repo.collection(id: expected.collectionID)
        #expect(response.dialog ==
            "Today’s passage is \(expected.reference) from the \(collection.name). \(text.text) (\(text.translation.name))")
    }
}
