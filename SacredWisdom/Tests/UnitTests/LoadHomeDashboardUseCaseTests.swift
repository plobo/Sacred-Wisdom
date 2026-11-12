import Foundation
import Testing
@testable import SacredWisdom

@Suite struct LoadHomeDashboardUseCaseTests {
    private func makeUseCase(
        religions: StubReligionRepository,
        passages: StubPassageRepository,
        recent: [ScripturePassage] = []
    ) -> LoadHomeDashboardUseCase {
        LoadHomeDashboardUseCase(
            loadSummaries: LoadReligionSummariesUseCase(religionRepository: religions),
            passageRepository: passages,
            recentPassages: StubRecentPassages(passages: recent)
        )
    }

    @Test func assemblesDashboard() async throws {
        let daily = Fixtures.passage("p1")
        let useCase = makeUseCase(
            religions: StubReligionRepository(
                religions: [Fixtures.religion("r1", order: 0), Fixtures.religion("r2", order: 1)],
                collections: [
                    Fixtures.collection("c1", religion: "r1", availability: .bundled),
                    Fixtures.collection("c2", religion: "r2", availability: .notDownloaded),
                ]
            ),
            passages: StubPassageRepository(daily: daily),
            recent: (0..<10).map { Fixtures.passage("p\($0)") }
        )

        let dashboard = try await useCase.execute(on: Date())

        #expect(dashboard.religions.count == 2)
        #expect(dashboard.dailyPassage == daily)
        #expect(dashboard.recentPassages.count == LoadHomeDashboardUseCase.recentLimit)
        #expect(dashboard.offlineCollectionCount == 1)
    }

    @Test func passageErrorFailsWholeDashboard() async {
        let useCase = makeUseCase(
            religions: StubReligionRepository(),
            passages: StubPassageRepository(error: .contentCorrupted("bad"))
        )
        await #expect(throws: AppError.contentCorrupted("bad")) {
            try await useCase.execute(on: Date())
        }
    }
}

@Suite struct LoadRecentPassagesUseCaseTests {
    @Test func joinsHistoryWithScriptureNewestFirstSkippingRemovedPassages() async throws {
        let useCase = LoadRecentPassagesUseCase(
            history: StubReadingHistory(passageIDs: ["p3", "gone", "p1", "p5"]),
            scripture: try Fixtures.repository()
        )
        #expect(try await useCase.execute(limit: 2).map(\.id) == ["p3", "p1"])
        #expect(try await useCase.execute(limit: 10).map(\.id) == ["p3", "p1", "p5"])
        #expect(try await useCase.execute(limit: 0).isEmpty)
    }

    @Test func historyFailureYieldsEmptyListInsteadOfError() async throws {
        let useCase = LoadRecentPassagesUseCase(
            history: StubReadingHistory(passageIDs: ["p1"], failure: .userData("down")),
            scripture: try Fixtures.repository()
        )
        #expect(try await useCase.execute(limit: 5).isEmpty)
    }

    @Test func scriptureFailureOtherThanNotFoundPropagates() async {
        let useCase = LoadRecentPassagesUseCase(
            history: StubReadingHistory(passageIDs: ["p1"]),
            scripture: UnavailableLibraryRepository(error: .database("closed"))
        )
        await #expect(throws: AppError.database("closed")) { try await useCase.execute(limit: 5) }
    }
}
