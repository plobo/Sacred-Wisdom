import Foundation
import Testing
@testable import SacredWisdom

@MainActor
@Suite struct SearchViewModelTests {
    private func makeViewModel(history: StubSearchHistory = StubSearchHistory()) async throws -> SearchViewModel {
        let repo = try await RepositoryKind.sqlite.make()
        return SearchViewModel(
            search: try await Fixtures.searchUseCase(),
            history: history,
            loadOptions: LoadSearchFilterOptionsUseCase(religions: repo, scripture: repo),
            debounce: .zero,
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    private func groups(_ vm: SearchViewModel) -> [String] {
        guard case .results(let results) = vm.phase else { return [] }
        return results.groups.map(\.religion.id)
    }

    @Test func typingSearchesWithoutRecordingHistory() async throws {
        let history = StubSearchHistory()
        let vm = try await makeViewModel(history: history)
        await vm.onAppear()
        #expect(vm.filterOptions?.religions.count == 2)
        vm.queryChanged("REF")
        await vm.waitForPendingSearch()
        #expect(groups(vm) == ["r1", "r2"])
        #expect(await history.items.isEmpty)
    }

    @Test func clearingTheQueryReturnsToIdle() async throws {
        let vm = try await makeViewModel()
        vm.queryChanged("REF")
        await vm.waitForPendingSearch()
        vm.queryChanged("  ")
        #expect(vm.phase == .idle)
    }

    @Test func submitRecordsHistoryAndShowsRecent() async throws {
        let history = StubSearchHistory()
        let vm = try await makeViewModel(history: history)
        vm.queryChanged("t2")
        await vm.submit()
        #expect(vm.recent.map(\.query) == ["t2"])
        #expect(groups(vm) == ["r1"])
    }

    @Test func noMatchesShowsEmpty() async throws {
        let vm = try await makeViewModel()
        vm.queryChanged("zzzz")
        await vm.waitForPendingSearch()
        #expect(vm.phase == .empty)
    }

    @Test func religionFilterRerunsSearch() async throws {
        let vm = try await makeViewModel()
        vm.queryChanged("REF")
        await vm.waitForPendingSearch()
        await vm.toggleReligion("r2")
        #expect(vm.isReligionSelected("r2"))
        #expect(groups(vm) == ["r2"])
        await vm.toggleReligion("r2")
        #expect(groups(vm) == ["r1", "r2"])
    }

    @Test func languageAndTranslationFiltersAndClear() async throws {
        let vm = try await makeViewModel()
        vm.queryChanged("REF")
        await vm.waitForPendingSearch()
        await vm.toggleTranslation("t3")
        #expect(groups(vm) == ["r2"])
        await vm.toggleLanguage("ar")
        #expect(vm.phase == .empty) // t3 is in c2, whose original is English
        await vm.clearFilters()
        #expect(vm.filters.isEmpty)
        #expect(groups(vm) == ["r1", "r2"])
    }

    @Test func selectingASuggestionSearchesAndRecords() async throws {
        let history = StubSearchHistory()
        let vm = try await makeViewModel(history: history)
        await vm.select("REF 5")
        #expect(vm.queryText == "REF 5")
        #expect(await history.items.map(\.query) == ["REF 5"])
        guard case .results(let results) = vm.phase else { Issue.record("expected results"); return }
        let full = results.groups.flatMap(\.results).filter(\.matchedAllTerms)
        #expect(full.map(\.passage.id) == ["p5"]) // fallback matches follow, grouped in fixed tradition order
    }

    @Test func removeAndClearRecent() async throws {
        let history = StubSearchHistory()
        let vm = try await makeViewModel(history: history)
        await vm.select("a1")
        await vm.select("b2")
        let first = try #require(vm.recent.first)
        await vm.removeRecent(first.id)
        #expect(vm.recent.map(\.query) == ["a1"])
        await vm.clearRecent()
        #expect(vm.recent.isEmpty)
    }

    @Test func searchFailureShowsError() async throws {
        let vm = SearchViewModel(
            search: SearchScriptureUseCase(search: FailingSearchRepository(), religions: StubReligionRepository()),
            history: StubSearchHistory(),
            loadOptions: LoadSearchFilterOptionsUseCase(religions: StubReligionRepository(), scripture: try Fixtures.repository()),
            debounce: .zero
        )
        await vm.select("x")
        #expect(vm.phase == .failed(AppError.unexpected("").userMessage))
    }
}

@MainActor
@Suite struct ReaderInitialTranslationTests {
    @Test func requestedTranslationWinsOverPreference() async throws {
        let store = InMemoryTranslationPreferenceStore()
        await store.setPreferredTranslationID("t1", collectionID: "c1")
        let vm = ReaderViewModel(start: .passage("p1"), initialTranslationID: "t2",
                                 loadPage: LoadReaderPageUseCase(repository: try Fixtures.repository()), preferences: store)
        await vm.load()
        #expect(vm.displayedText?.text == "[t2-1]")
        #expect(await store.preferredTranslationID(collectionID: "c1") == "t1") // not overwritten
    }

    @Test func unknownRequestedTranslationFallsBack() async throws {
        let vm = ReaderViewModel(start: .passage("p1"), initialTranslationID: "t3",
                                 loadPage: LoadReaderPageUseCase(repository: try Fixtures.repository()),
                                 preferences: InMemoryTranslationPreferenceStore())
        await vm.load()
        #expect(vm.selectedTranslationID == "t1")
    }
}

/// History that fails every write, to check failures are surfaced rather than swallowed.
private struct FailingHistory: SearchHistoryRepository {
    func recent(limit: Int) async throws(AppError) -> [SearchHistoryItem] { [] }
    func record(_ query: String, at date: Date) async throws(AppError) { throw .userData("x") }
    func remove(id: UUID) async throws(AppError) { throw .userData("x") }
    func clear() async throws(AppError) { throw .userData("x") }
}

@MainActor
@Suite struct SearchHistoryErrorTests {
    @Test func failedClearAndRemoveShowAnError() async throws {
        let repo = try Fixtures.repository()
        let vm = SearchViewModel(search: try await Fixtures.searchUseCase(), history: FailingHistory(),
                                 loadOptions: LoadSearchFilterOptionsUseCase(religions: repo, scripture: repo))
        await vm.clearRecent()
        #expect(vm.actionError == AppError.userData("").userMessage)
        vm.actionError = nil
        await vm.removeRecent(UUID())
        #expect(vm.actionError != nil)
    }
}
