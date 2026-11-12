import Testing
@testable import SacredWisdom

@Suite struct LoadCollectionContentsUseCaseTests {
    @Test func returnsBooksWithSectionsInOrder() async throws {
        let contents = try await LoadCollectionContentsUseCase(repository: Fixtures.repository()).execute(collectionID: "c1")
        #expect(contents.collection.id == "c1")
        #expect(contents.translations.map(\.id) == ["t1", "t2"])
        #expect(contents.books.map(\.book.id) == ["b1", "b2"])
        #expect(contents.books[0].sections.map(\.id) == ["s1a", "s1b"])
    }

    @Test func unknownCollectionFails() async throws {
        let useCase = LoadCollectionContentsUseCase(repository: try Fixtures.repository())
        await #expect(throws: AppError.self) { try await useCase.execute(collectionID: "nope") }
    }
}

@Suite struct LoadReaderPageUseCaseTests {
    @Test func sectionStartOpensFirstPassage() async throws {
        let page = try await LoadReaderPageUseCase(repository: Fixtures.repository()).execute(.section("s1b"))
        #expect(page.passage.id == "p3")
        #expect(page.section.id == "s1b")
        #expect(page.book.id == "b1")
        #expect(page.previousPassageID == "p2")
        #expect(page.nextPassageID == "p4")
    }

    @Test func passageStartAtCollectionEdges() async throws {
        let useCase = LoadReaderPageUseCase(repository: try Fixtures.repository())
        let first = try await useCase.execute(.passage("p1"))
        #expect(first.previousPassageID == nil)
        #expect(first.nextPassageID == "p2")
        let only = try await useCase.execute(.passage("p5"))
        #expect(only.previousPassageID == nil && only.nextPassageID == nil)
    }

    @Test func emptyOrUnknownSectionFails() async throws {
        let useCase = LoadReaderPageUseCase(repository: try Fixtures.repository())
        await #expect(throws: AppError.self) { try await useCase.execute(.section("nope")) }
    }
}
