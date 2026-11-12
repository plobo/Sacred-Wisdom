import Foundation
import Testing
@testable import SacredWisdom

/// Universal search over the real bundled content in SQLite (no network involved).
@Suite struct UniversalSearchIntegrationTests {
    private static let allTraditions = ["hinduism", "christianity", "islam", "judaism", "buddhism", "sikhism"]

    private func useCase() throws -> SearchScriptureUseCase {
        let url = try #require(Bundle(for: AppDependencies.self)
            .url(forResource: SampleLibraryRepository.resourceName, withExtension: "json"))
        let database = DatabaseManager(location: .inMemory,
                                       bundledPackages: [.init(id: SampleLibraryRepository.resourceName, url: url)])
        let sqlite = SQLiteScriptureRepository(database: database)
        return SearchScriptureUseCase(
            search: LocalKeywordSearchRepository(index: FullTextSearchIndex(database: database), scripture: sqlite),
            religions: sqlite
        )
    }

    @Test func oneQuerySearchesAllSixCollections() async throws {
        let results = try await useCase().execute("the", filters: SearchFilters())
        #expect(results.groups.map(\.religion.id) == Self.allTraditions)
    }

    @Test func resultsCarryAccurateReferences() async throws {
        let results = try await useCase().execute("peacemakers", filters: SearchFilters())
        let only = try #require(results.groups.first?.results.first)
        #expect(results.totalCount == 1)
        #expect(only.passage.id == "bible.matthew.5.9")
        #expect(only.passage.reference == "Matthew 5:9")
        #expect(only.previewText?.text == "Blessed are the peacemakers: for they shall be called the children of God.")
    }

    @Test func exactPhraseMatchesOnlyConsecutiveWords() async throws {
        let phrase = try await useCase().execute(#""still waters""#, filters: SearchFilters())
        #expect(phrase.groups.flatMap(\.results).map(\.passage.id) == ["tanakh.psalms.23.2"])
    }

    @Test func translationMatchIsReportedForTheMatchingTranslation() async throws {
        // "gentle" appears only in the World English Bible (KJV has "meek").
        let results = try await useCase().execute("gentle", filters: SearchFilters())
        let result = try #require(results.groups.first?.results.first)
        #expect(result.passage.id == "bible.matthew.5.5")
        #expect(result.matchedTranslationID == "bible-web")
        #expect(result.previewText?.text == "Blessed are the gentle, for they shall inherit the earth.")
    }

    @Test func filtersRestrictResults() async throws {
        let useCase = try useCase()
        let islam = try await useCase.execute("the", filters: SearchFilters(religionIDs: ["islam"]))
        #expect(islam.groups.map(\.religion.id) == ["islam"])
        let arabic = try await useCase.execute("the", filters: SearchFilters(languageCodes: ["ar"]))
        #expect(arabic.groups.map(\.religion.id) == ["islam"])
        let muller = try await useCase.execute("hatred", filters: SearchFilters(translationIDs: ["dhp-muller"]))
        #expect(muller.groups.flatMap(\.results).allSatisfy { $0.matchedTranslationID == "dhp-muller" })
        #expect(!muller.isEmpty)
        let collection = try await useCase.execute("the", filters: SearchFilters(collectionIDs: ["tanakh"]))
        #expect(collection.groups.map(\.religion.id) == ["judaism"])
    }

    @Test(arguments: SearchSuggestionProvider.suggestedQuestions)
    func everySuggestedQuestionFindsPassages(question: String) async throws {
        #expect(try await !useCase().execute(question, filters: SearchFilters()).isEmpty)
    }

    @Test func unpointedArabicQueryFindsTheQuran() async throws {
        let results = try await useCase().execute("الرحيم", filters: SearchFilters())
        #expect(results.groups.flatMap(\.results).map(\.passage.reference).sorted() == ["Al-Fatihah 1:1", "Al-Fatihah 1:3"])
    }
}
