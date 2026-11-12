import Foundation
import Testing
@testable import SacredWisdom

@MainActor
@Suite struct FavoritesViewModelTests {
    private func makeViewModel() throws -> (FavoritesViewModel, UserDataContext) {
        let context = try Fixtures.userData()
        let vm = FavoritesViewModel(
            loadFavorites: LoadFavoritesUseCase(bookmarks: context.bookmarks, scripture: try Fixtures.repository()),
            userData: context
        )
        return (vm, context)
    }

    @Test func emptyStateWhenNothingSaved() async throws {
        let (vm, _) = try makeViewModel()
        await vm.load()
        #expect(vm.content?.items.isEmpty == true)
        #expect(!vm.hasBookmarks)
    }

    @Test func listsSavedPassagesNewestFirstAndKeepsUnavailableOnes() async throws {
        let (vm, context) = try makeViewModel()
        try await context.bookmarks.addBookmark(passageID: "p1", at: Date(timeIntervalSince1970: 1))
        try await context.bookmarks.addBookmark(passageID: "removed-from-library", at: Date(timeIntervalSince1970: 2))
        try await context.bookmarks.addBookmark(passageID: "p5", at: Date(timeIntervalSince1970: 3))
        await vm.load()
        #expect(vm.visibleItems.map(\.id) == ["p5", "removed-from-library", "p1"])
        #expect(vm.visibleItems[0].religion?.id == "r2")
        #expect(vm.visibleItems[1].passage == nil)
    }

    @Test func filtersByCollectionAndUnfiled() async throws {
        let (vm, context) = try makeViewModel()
        let study = try await context.bookmarks.createCollection(named: "Study", at: Date())
        try await context.bookmarks.addBookmark(passageID: "p1", at: Date(timeIntervalSince1970: 1))
        try await context.bookmarks.addBookmark(passageID: "p3", at: Date(timeIntervalSince1970: 2))
        try await context.bookmarks.moveBookmark(passageID: "p3", toCollection: study.id)
        await vm.load()

        vm.select(.collection(study.id))
        #expect(vm.visibleItems.map(\.id) == ["p3"])
        #expect(vm.collectionName(for: vm.visibleItems[0]) == "Study")
        vm.select(.unfiled)
        #expect(vm.visibleItems.map(\.id) == ["p1"])
        vm.select(.all)
        #expect(vm.visibleItems.count == 2)
    }

    @Test func searchMatchesReferenceTextAndNoteIgnoringCase() async throws {
        let (vm, context) = try makeViewModel()
        try await context.bookmarks.addBookmark(passageID: "p1", at: Date(timeIntervalSince1970: 1))
        try await context.bookmarks.setNote("Thoughts on Ḥesed", passageID: "p4", at: Date(timeIntervalSince1970: 2))
        await vm.load()

        vm.searchText = "ref 1"
        #expect(vm.visibleItems.map(\.id) == ["p1"])
        vm.searchText = "t2-4"
        #expect(vm.visibleItems.map(\.id) == ["p4"])
        vm.searchText = "HESED thoughts"
        #expect(vm.visibleItems.map(\.id) == ["p4"])
        vm.searchText = "nothing like this"
        #expect(vm.visibleItems.isEmpty)
    }

    @Test func removingNotedBookmarkAsksFirstPlainOneDoesNot() async throws {
        let (vm, context) = try makeViewModel()
        try await context.bookmarks.addBookmark(passageID: "p1", at: Date(timeIntervalSince1970: 1))
        try await context.bookmarks.setNote("Keep", passageID: "p3", at: Date(timeIntervalSince1970: 2))
        await vm.load()

        let plain = try #require(vm.visibleItems.first { $0.id == "p1" })
        await vm.remove(plain)
        #expect(vm.visibleItems.map(\.id) == ["p3"])

        let noted = try #require(vm.visibleItems.first)
        await vm.remove(noted)
        #expect(vm.pendingRemoval?.id == "p3")
        #expect(vm.visibleItems.count == 1)
        await vm.confirmRemoval()
        #expect(vm.visibleItems.isEmpty)
        #expect(context.changes.bookmarks == 2)
    }

    @Test func creatingCollectionSelectsItAndDeletingFallsBackToAll() async throws {
        let (vm, context) = try makeViewModel()
        try await context.bookmarks.addBookmark(passageID: "p1", at: Date())
        await vm.load()
        await vm.createCollection(named: "Psalms study")
        let created = try #require(vm.collections.first)
        #expect(vm.filter == .collection(created.id))

        let item = try #require(vm.content?.items.first)
        await vm.move(item, to: created.id)
        #expect(vm.visibleItems.map(\.id) == ["p1"])

        await vm.renameCollection(created.id, to: "Psalms")
        #expect(vm.collections.map(\.name) == ["Psalms"])

        await vm.deleteCollection(created.id)
        #expect(vm.filter == .all)
        #expect(vm.content?.items.first?.bookmark.collectionID == nil)
    }

    @Test func loadFailureShowsError() async throws {
        let context = UserDataContext(bookmarks: FailingBookmarkRepository(), history: StubReadingHistory(),
                                      changes: UserDataChanges())
        let vm = FavoritesViewModel(
            loadFavorites: LoadFavoritesUseCase(bookmarks: context.bookmarks, scripture: try Fixtures.repository()),
            userData: context
        )
        await vm.load()
        #expect(vm.state == .failed(AppError.userData("").userMessage))
    }
}

@MainActor
@Suite struct UserDataIntegrationInViewModelsTests {
    @Test func readerRecordsEveryPassageShownAndTracksBookmark() async throws {
        let context = try Fixtures.userData(now: { Date() }) // real clock: the two views need distinct times
        let vm = ReaderViewModel(start: .passage("p1"), loadPage: LoadReaderPageUseCase(repository: try Fixtures.repository()),
                                 preferences: InMemoryTranslationPreferenceStore(), userData: context)
        await vm.load()
        await vm.goToNext()
        #expect(try await context.history.recent(limit: 5).map(\.passageID) == ["p2", "p1"])

        await vm.bookmarks.toggle()
        #expect(try await context.bookmarks.bookmarkedPassageIDs() == ["p2"])
        await vm.goToPrevious()
        #expect(!vm.bookmarks.isBookmarked) // p1 is not saved
    }

    @Test func searchTogglesBookmarksFromResults() async throws {
        let context = try Fixtures.userData()
        let vm = SearchViewModel(search: try await Fixtures.searchUseCase(), history: StubSearchHistory(),
                                 loadOptions: LoadSearchFilterOptionsUseCase(religions: try Fixtures.repository(),
                                                                             scripture: try Fixtures.repository()),
                                 debounce: .zero, userData: context)
        await vm.toggleBookmark("p5")
        #expect(vm.isBookmarked("p5"))
        #expect(context.changes.bookmarks == 1)

        try await context.bookmarks.setNote("note", passageID: "p5", at: Date())
        await vm.toggleBookmark("p5")
        #expect(vm.pendingRemovalID == "p5")
        await vm.confirmRemoval()
        #expect(!vm.isBookmarked("p5"))
    }

    @Test func homeRefreshPicksUpNewHistoryWithoutLoadingState() async throws {
        let repo = try Fixtures.repository()
        let context = try Fixtures.userData()
        let vm = HomeViewModel(
            loadDashboard: LoadHomeDashboardUseCase(
                loadSummaries: LoadReligionSummariesUseCase(religionRepository: repo),
                passageRepository: repo,
                recentPassages: LoadRecentPassagesUseCase(history: context.history, scripture: repo)
            ),
            changes: context.changes
        )
        await vm.refresh() // ignored before the first load
        #expect(vm.state == .idle)
        await vm.load()
        guard case .loaded(let before) = vm.state else { Issue.record("not loaded"); return }
        #expect(before.recentPassages.isEmpty)

        await context.recordView(of: "p4")
        #expect(vm.readingHistoryRevision == 1)
        await vm.refresh()
        guard case .loaded(let after) = vm.state else { Issue.record("not loaded"); return }
        #expect(after.recentPassages.map(\.id) == ["p4"])
    }

    @Test func settingsClearsReadingHistory() async throws {
        let context = try Fixtures.userData()
        await context.recordView(of: "p1")
        let vm = SettingsViewModel(userData: context)
        await vm.clearReadingHistory()
        #expect(try await context.history.recent(limit: 5).isEmpty)
        #expect(vm.statusMessage == "Reading history cleared.")
        #expect(context.changes.readingHistory == 2)
    }
}
