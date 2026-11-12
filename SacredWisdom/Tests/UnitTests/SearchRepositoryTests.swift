import Foundation
import Testing
@testable import SacredWisdom

@Suite struct LocalKeywordSearchRepositoryTests {
    @Test func returnsOneResultPerPassageWithMatchedTranslation() async throws {
        let repo = try await Fixtures.keywordSearch()
        let results = try await repo.search(query: SearchQueryParser.parse("t2"), filters: SearchFilters())
        #expect(Set(results.map(\.id)) == ["p1", "p4"])
        #expect(results.allSatisfy { $0.matchedTranslationID == "t2" && $0.matchedAllTerms })
        #expect(results.first?.previewText?.text.hasPrefix("[t2-") == true)
    }

    @Test func passageMatchingSeveralTranslationsAppearsOnceInTheDefaultTranslation() async throws {
        let repo = try await Fixtures.keywordSearch()
        let results = try await repo.search(query: SearchQueryParser.parse("REF"), filters: SearchFilters())
        #expect(results.count == 5)
        #expect(Set(results.map(\.id)).count == 5)
        // p1 and p4 match in both t1 and t2; t1 is c1's default.
        #expect(results.filter { ["p1", "p4"].contains($0.id) }.allSatisfy { $0.matchedTranslationID == "t1" })
    }

    @Test func fallsBackToAnyWordAndRanksFullMatchesFirst() async throws {
        let repo = try await Fixtures.keywordSearch()
        let results = try await repo.search(query: SearchQueryParser.parse("o1 t1"), filters: SearchFilters())
        #expect(results.first?.id == "p1")
        #expect(results.first?.matchedAllTerms == true)
        #expect(results.dropFirst().allSatisfy { !$0.matchedAllTerms })
        #expect(Set(results.map(\.id)) == ["p1", "p2", "p3", "p4"])
    }

    @Test func respectsFiltersAndEmptyQuery() async throws {
        let repo = try await Fixtures.keywordSearch()
        let filtered = try await repo.search(query: SearchQueryParser.parse("REF"), filters: SearchFilters(religionIDs: ["r2"]))
        #expect(filtered.map(\.id) == ["p5"])
        #expect(try await repo.search(query: SearchQueryParser.parse(""), filters: SearchFilters()).isEmpty)
    }
}

@Suite struct CombinedSearchRepositoryTests {
    @Test func supplementaryFailureDoesNotBreakKeywordSearch() async throws {
        let combined = CombinedSearchRepository(primary: try await Fixtures.keywordSearch(),
                                                supplementary: [FailingSearchRepository()])
        let results = try await combined.search(query: SearchQueryParser.parse("t2"), filters: SearchFilters())
        #expect(Set(results.map(\.id)) == ["p1", "p4"])
    }

    @Test func supplementaryResultsAreAppendedWithoutDuplicates() async throws {
        let extra = [
            ScriptureSearchResult(passage: Fixtures.passage("p1"), matchedTranslationID: "t1", score: 1, matchedAllTerms: false),
            ScriptureSearchResult(passage: Fixtures.passage("x9"), matchedTranslationID: "t1", score: 1, matchedAllTerms: false),
        ]
        let combined = CombinedSearchRepository(primary: try await Fixtures.keywordSearch(),
                                                supplementary: [FixedSearchRepository(results: extra)])
        let ids = try await combined.search(query: SearchQueryParser.parse("t2"), filters: SearchFilters()).map(\.id)
        #expect(ids.count == 3)
        #expect(ids.last == "x9")
    }

    @Test func primaryFailureIsReported() async {
        let combined = CombinedSearchRepository(primary: FailingSearchRepository(), supplementary: [])
        await #expect(throws: AppError.self) {
            try await combined.search(query: SearchQueryParser.parse("x"), filters: SearchFilters())
        }
    }
}

@Suite struct SearchScriptureUseCaseTests {
    @Test func groupsByTraditionInFixedOrder() async throws {
        let results = try await Fixtures.searchUseCase().execute("REF", filters: SearchFilters())
        #expect(results.groups.map(\.religion.id) == ["r1", "r2"])
        #expect(results.totalCount == 5)
        #expect(results.groups[1].collectionNames["c2"] == "C2")
    }

    @Test func emptyQueryReturnsNoGroups() async throws {
        let results = try await Fixtures.searchUseCase().execute("   ", filters: SearchFilters())
        #expect(results.isEmpty)
    }
}

@Suite struct LoadSearchFilterOptionsUseCaseTests {
    @Test func collectsLanguagesAndTranslations() async throws {
        let repo = try await RepositoryKind.sqlite.make()
        let options = try await LoadSearchFilterOptionsUseCase(religions: repo, scripture: repo).execute()
        #expect(options.religions.map(\.id) == ["r1", "r2"])
        #expect(Set(options.languageCodes) == ["ar", "en"])
        #expect(Set(options.translations.map(\.id)) == ["t1", "t2", "t3"])
    }
}

@Suite struct SwiftDataSearchHistoryRepositoryTests {
    private func makeRepository() throws -> SwiftDataSearchHistoryRepository {
        SwiftDataSearchHistoryRepository(modelContainer: try PersistenceManager.makeContainer(location: .inMemory))
    }

    @Test func recordsNewestFirstAndDeduplicates() async throws {
        let repo = try makeRepository()
        let t0 = Date(timeIntervalSince1970: 0)
        try await repo.record("peace", at: t0)
        try await repo.record("mercy", at: t0.addingTimeInterval(1))
        try await repo.record("  Peace ", at: t0.addingTimeInterval(2))
        let recent = try await repo.recent(limit: 10)
        #expect(recent.map(\.query) == ["Peace", "mercy"])
    }

    @Test func ignoresBlankAndCapsEntries() async throws {
        let repo = try makeRepository()
        try await repo.record("  ?! ", at: Date())
        #expect(try await repo.recent(limit: 10).isEmpty)
        for i in 0..<(SwiftDataSearchHistoryRepository.maximumEntries + 5) {
            try await repo.record("q\(i)", at: Date(timeIntervalSince1970: Double(i)))
        }
        let all = try await repo.recent(limit: 100)
        #expect(all.count == SwiftDataSearchHistoryRepository.maximumEntries)
        #expect(all.first?.query == "q\(SwiftDataSearchHistoryRepository.maximumEntries + 4)")
    }

    @Test func removeAndClear() async throws {
        let repo = try makeRepository()
        try await repo.record("peace", at: Date(timeIntervalSince1970: 1))
        try await repo.record("mercy", at: Date(timeIntervalSince1970: 2))
        let mercy = try #require(try await repo.recent(limit: 1).first)
        try await repo.remove(id: mercy.id)
        #expect(try await repo.recent(limit: 10).map(\.query) == ["peace"])
        try await repo.clear()
        #expect(try await repo.recent(limit: 10).isEmpty)
    }

    @Test func historyPersistsInTheContainer() async throws {
        let container = try PersistenceManager.makeContainer(location: .inMemory)
        try await SwiftDataSearchHistoryRepository(modelContainer: container).record("shepherd", at: Date())
        #expect(try await SwiftDataSearchHistoryRepository(modelContainer: container).recent(limit: 5).map(\.query) == ["shepherd"])
    }
}
