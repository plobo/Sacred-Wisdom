import Testing
@testable import SacredWisdom

@Suite struct LoadReligionSummariesUseCaseTests {
    @Test func sortsBySortOrderAndJoinsCollections() async throws {
        let repo = StubReligionRepository(
            religions: [Fixtures.religion("b", order: 1), Fixtures.religion("a", order: 0)],
            collections: [Fixtures.collection("cb", religion: "b")]
        )
        let summaries = try await LoadReligionSummariesUseCase(religionRepository: repo).execute()

        #expect(summaries.map(\.id) == ["a", "b"])
        #expect(summaries[0].collection == nil)
        #expect(summaries[1].collection?.id == "cb")
    }

    @Test func propagatesTypedError() async {
        let repo = StubReligionRepository(error: .contentNotFound("x"))
        await #expect(throws: AppError.contentNotFound("x")) {
            try await LoadReligionSummariesUseCase(religionRepository: repo).execute()
        }
    }
}
