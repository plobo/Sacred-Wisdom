import Testing
@testable import SacredWisdom

@MainActor
@Suite struct ReaderViewModelTests {
    private func makeViewModel(
        start: ReaderStart = .section("s1a"),
        preferences: InMemoryTranslationPreferenceStore = InMemoryTranslationPreferenceStore()
    ) throws -> ReaderViewModel {
        ReaderViewModel(
            start: start,
            loadPage: LoadReaderPageUseCase(repository: try Fixtures.repository()),
            preferences: preferences
        )
    }

    @Test func loadShowsFirstPassageWithDefaultTranslation() async throws {
        let vm = try makeViewModel()
        await vm.load()
        #expect(vm.page?.passage.id == "p1")
        #expect(vm.selectedTranslationID == "t1")
        #expect(vm.displayedText?.text == "[t1-1]")
        #expect(vm.hasTranslationChoice)
        #expect(vm.isOriginalRightToLeft)
        #expect(!vm.canGoPrevious)
        #expect(vm.canGoNext)
    }

    @Test func nextAndPreviousWalkReadingOrder() async throws {
        let vm = try makeViewModel()
        await vm.load()
        await vm.goToNext()
        #expect(vm.page?.passage.id == "p2")
        await vm.goToNext()
        #expect(vm.page?.passage.id == "p3")
        await vm.goToPrevious()
        #expect(vm.page?.passage.id == "p2")
    }

    @Test func nextAtEndIsANoOp() async throws {
        let vm = try makeViewModel(start: .passage("p4"))
        await vm.load()
        #expect(!vm.canGoNext)
        await vm.goToNext()
        #expect(vm.page?.passage.id == "p4")
    }

    @Test func translationSelectionPersistsAcrossPassagesAndReaders() async throws {
        let store = InMemoryTranslationPreferenceStore()
        let vm = try makeViewModel(preferences: store)
        await vm.load()
        await vm.selectTranslation("t2")
        #expect(vm.displayedText?.text == "[t2-1]")

        await vm.goToNext() // p2 has no t2 text: falls back to default, selection is kept
        #expect(vm.selectedTranslationID == "t2")
        #expect(vm.displayedText?.translation.id == "t1")

        let another = try makeViewModel(start: .passage("p4"), preferences: store)
        await another.load()
        #expect(another.displayedText?.text == "[t2-4]")
    }

    @Test func selectingUnknownTranslationIsIgnored() async throws {
        let vm = try makeViewModel()
        await vm.load()
        await vm.selectTranslation("t3") // belongs to another collection
        #expect(vm.selectedTranslationID == "t1")
    }

    @Test func fontScaleIsBounded() throws {
        let vm = try makeViewModel()
        for _ in 0..<20 { vm.increaseFontSize() }
        #expect(vm.fontScale == ReaderViewModel.fontScaleRange.upperBound)
        #expect(!vm.canIncreaseFontSize)
        for _ in 0..<20 { vm.decreaseFontSize() }
        #expect(vm.fontScale == ReaderViewModel.fontScaleRange.lowerBound)
        #expect(!vm.canDecreaseFontSize)
    }

    @Test func unknownStartShowsError() async throws {
        let vm = try makeViewModel(start: .passage("nope"))
        await vm.load()
        #expect(vm.state == .failed(AppError.contentNotFound("").userMessage))
    }
}

@MainActor
@Suite struct CollectionBrowserViewModelTests {
    @Test func loadsContents() async throws {
        let vm = CollectionBrowserViewModel(
            collectionID: "c1",
            loadContents: LoadCollectionContentsUseCase(repository: try Fixtures.repository())
        )
        await vm.load()
        guard case .loaded(let contents) = vm.state else {
            Issue.record("Expected loaded state, got \(vm.state)")
            return
        }
        #expect(contents.books.count == 2)
        #expect(vm.languageSummary?.hasSuffix("2 translations") == true)
    }

    @Test func unknownCollectionShowsError() async throws {
        let vm = CollectionBrowserViewModel(
            collectionID: "nope",
            loadContents: LoadCollectionContentsUseCase(repository: try Fixtures.repository())
        )
        await vm.load()
        #expect(vm.state == .failed(AppError.contentNotFound("").userMessage))
    }
}
