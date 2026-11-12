import Foundation
import Testing
@testable import SacredWisdom

@Suite struct LoadPassageDetailUseCaseTests {
    @Test(arguments: RepositoryKind.allCases)
    func assemblesContextThemesAndRelated(kind: RepositoryKind) async throws {
        let repo = try await kind.make()
        let detail = try await LoadPassageDetailUseCase(scripture: repo, related: repo).execute(passageID: "p2")
        #expect(detail.religion.id == "r1")
        #expect(detail.collection.id == "c1")
        #expect(detail.book.id == "b1")
        #expect(detail.section.id == "s1a")
        #expect(detail.positionInSection == 2)
        #expect(detail.sectionPassageCount == 2)
        #expect(detail.themes.isEmpty)
        #expect(detail.related.isEmpty)

        let tagged = try await LoadPassageDetailUseCase(scripture: repo, related: repo).execute(passageID: "p1")
        #expect(tagged.themes.map(\.id) == ["th1"])
        #expect(tagged.related.map(\.passage.id) == ["p5"])
    }

    @Test func unknownPassageThrowsNotFound() async throws {
        let repo = try Fixtures.repository()
        await #expect(throws: AppError.contentNotFound("passage nope")) {
            try await LoadPassageDetailUseCase(scripture: repo, related: repo).execute(passageID: "nope")
        }
    }
}

@MainActor
@Suite struct PassageDetailViewModelTests {
    private func makeViewModel(
        _ passageID: String = "p1",
        translationID: String? = nil,
        preferences: InMemoryTranslationPreferenceStore = InMemoryTranslationPreferenceStore(),
        userData: UserDataContext? = nil
    ) throws -> (PassageDetailViewModel, UserDataContext) {
        let repo = try Fixtures.repository()
        let context = try userData ?? Fixtures.userData()
        let vm = PassageDetailViewModel(
            passageID: passageID, initialTranslationID: translationID,
            loadDetail: LoadPassageDetailUseCase(scripture: repo, related: repo),
            preferences: preferences, userData: context
        )
        return (vm, context)
    }

    @Test func loadShowsDetailAndRecordsReadingHistory() async throws {
        let (vm, context) = try makeViewModel()
        await vm.load()
        #expect(vm.detail?.passage.reference == "REF 1")
        #expect(try await context.history.recent(limit: 5).map(\.passageID) == ["p1"])
        #expect(context.changes.readingHistory == 1)
    }

    @Test func primaryTranslationIsRequestedThenPreferredThenDefault() async throws {
        let (requested, _) = try makeViewModel(translationID: "t2")
        await requested.load()
        #expect(requested.orderedTexts.map(\.translation.id) == ["t2", "t1"])

        let preferences = InMemoryTranslationPreferenceStore()
        await preferences.setPreferredTranslationID("t2", collectionID: "c1")
        let (preferred, _) = try makeViewModel(preferences: preferences)
        await preferred.load()
        #expect(preferred.primaryTranslationID == "t2")

        let (fallback, _) = try makeViewModel(translationID: "not-in-this-collection")
        await fallback.load()
        #expect(fallback.orderedTexts.map(\.translation.id) == ["t1", "t2"])
    }

    @Test func unknownPassageShowsError() async throws {
        let (vm, context) = try makeViewModel("nope")
        await vm.load()
        #expect(vm.state == .failed(AppError.contentNotFound("").userMessage))
        #expect(try await context.history.recent(limit: 5).isEmpty)
    }

    @Test func bookmarkToggleAndNoteRoundTrip() async throws {
        let (vm, context) = try makeViewModel()
        await vm.load()
        #expect(!vm.bookmarks.isBookmarked)

        await vm.bookmarks.toggle()
        #expect(vm.bookmarks.isBookmarked)
        #expect(context.changes.bookmarks == 1)

        await vm.bookmarks.saveNote("Compare with REF 5")
        #expect(vm.bookmarks.note == "Compare with REF 5")
        #expect(try await context.bookmarks.bookmark(passageID: "p1")?.note == "Compare with REF 5")
    }

    @Test func removingBookmarkWithNoteNeedsConfirmation() async throws {
        let (vm, context) = try makeViewModel()
        await vm.load()
        await vm.bookmarks.saveNote("Keep me")

        await vm.bookmarks.toggle()
        #expect(vm.bookmarks.isConfirmingRemoval)
        #expect(vm.bookmarks.isBookmarked)

        vm.bookmarks.cancelRemoval()
        #expect(!vm.bookmarks.isConfirmingRemoval)
        #expect(try await context.bookmarks.bookmark(passageID: "p1") != nil)

        await vm.bookmarks.toggle()
        await vm.bookmarks.confirmRemoval()
        #expect(!vm.bookmarks.isBookmarked)
        #expect(try await context.bookmarks.bookmark(passageID: "p1") == nil)
    }

    @Test func noteSavedWithoutBookmarkBookmarksThePassage() async throws {
        let (vm, _) = try makeViewModel()
        await vm.load()
        await vm.bookmarks.saveNote("A reflection")
        #expect(vm.bookmarks.isBookmarked)
    }

    @Test func newCollectionFilesTheBookmark() async throws {
        let (vm, _) = try makeViewModel()
        await vm.load()
        await vm.bookmarks.createCollectionAndMove(named: "Study")
        #expect(vm.bookmarks.isBookmarked)
        #expect(vm.bookmarks.collectionName == "Study")
        await vm.bookmarks.move(toCollection: nil)
        #expect(vm.bookmarks.collectionName == nil)
    }

    @Test func failedWriteSurfacesErrorMessage() async throws {
        let failing = UserDataContext(bookmarks: FailingBookmarkRepository(), history: StubReadingHistory(),
                                      changes: UserDataChanges())
        let (vm, _) = try makeViewModel(userData: failing)
        await vm.load()
        await vm.bookmarks.toggle()
        #expect(vm.bookmarks.actionError == AppError.userData("").userMessage)
        #expect(!vm.bookmarks.isBookmarked)
    }

    @Test func externalBookmarkChangeIsPickedUpOnRefresh() async throws {
        let (vm, context) = try makeViewModel()
        await vm.load()
        try await context.bookmarks.addBookmark(passageID: "p1", at: Date())
        await vm.bookmarks.refresh()
        #expect(vm.bookmarks.isBookmarked)
    }

    @Test func shareTextUsesPrimaryTranslation() async throws {
        let (vm, _) = try makeViewModel(translationID: "t2")
        await vm.load()
        let text = try #require(vm.shareText)
        #expect(text.contains("[t2-1]"))
        #expect(!text.contains("[t1-1]"))
    }
}

@Suite struct PassageShareFormatterTests {
    private let kjv = Translation(
        id: "kjv", collectionID: "bible", name: "King James Version", languageCode: "en", translator: "",
        year: 1769, source: ContentSource(id: "kjv", name: "KJV", url: nil, license: "Public domain",
                                          attribution: "King James Version, 1769 Oxford standard text.")
    )

    @Test func includesReferenceVerbatimTextTranslationAndAttribution() {
        // Real text (Matthew 5:9, KJV), as in the bundled library.
        let text = "Blessed are the peacemakers: for they shall be called the children of God."
        let passage = ScripturePassage(
            id: "bible.matthew.5.9", religionID: "christianity", collectionID: "bible", bookID: "b", sectionID: "s",
            sequence: 9, reference: "Matthew 5:9", originalLanguage: "en", originalText: nil, originalSource: nil,
            texts: [PassageText(translation: kjv, text: text)]
        )
        let shared = PassageShareFormatter.text(for: passage, collectionName: "Bible", translationID: nil)
        #expect(shared == """
            Matthew 5:9 · Bible

            Blessed are the peacemakers: for they shall be called the children of God.
            — King James Version

            King James Version, 1769 Oxford standard text. Public domain.
            Shared from Sacred Wisdom
            """)
    }

    @Test func creditsTheOriginalTextSourceWhenTheOriginalIsShared() {
        let tanzil = ContentSource(id: "tanzil", name: "Tanzil", url: nil, license: "Tanzil license",
                                   attribution: "Quran text © Tanzil Project (tanzil.net).")
        let passage = ScripturePassage(
            id: "x", religionID: "r", collectionID: "c", bookID: "b", sectionID: "s", sequence: 1, reference: "REF",
            originalLanguage: "ar", originalText: "[original]", originalSource: tanzil,
            texts: [PassageText(translation: kjv, text: "[translation]")]
        )
        let shared = PassageShareFormatter.text(for: passage, collectionName: "C", translationID: "kjv")
        #expect(shared.contains("[original]\n\n[translation]"))
        #expect(shared.contains("Original text: Quran text © Tanzil Project (tanzil.net). Tanzil license."))
    }
}
