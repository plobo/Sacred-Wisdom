import Foundation
import Testing
@testable import SacredWisdom

@MainActor
@Suite struct HomeViewModelTests {
    private let empty = HomeDashboard(religions: [], dailyPassage: nil, recentPassages: [])

    @Test func loadSuccessSetsLoadedState() async {
        let vm = HomeViewModel(loadDashboard: StubDashboardUseCase(result: .success(empty)))
        #expect(vm.state == .idle)
        await vm.load()
        #expect(vm.state == .loaded(empty))
    }

    @Test func loadFailureSetsUserFacingMessage() async {
        let error = AppError.contentNotFound("sample_library.json")
        let vm = HomeViewModel(loadDashboard: StubDashboardUseCase(result: .failure(error)))
        await vm.load()
        #expect(vm.state == .failed(error.userMessage))
    }

    @Test(arguments: [(6, "Good morning"), (13, "Good afternoon"), (20, "Good evening"), (2, "Good evening")])
    func greetingDependsOnHour(hour: Int, expected: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour)))
        let vm = HomeViewModel(
            loadDashboard: StubDashboardUseCase(result: .success(empty)),
            now: { date },
            calendar: calendar
        )
        #expect(vm.greeting == expected)
    }

    @Test func offlineSummaryAndReligionNameAfterLoad() async {
        let dashboard = HomeDashboard(
            religions: [
                ReligionSummary(religion: Fixtures.religion("r1", order: 0), collection: Fixtures.collection("c1", religion: "r1")),
                ReligionSummary(religion: Fixtures.religion("r2", order: 1), collection: nil),
            ],
            dailyPassage: nil,
            recentPassages: []
        )
        let vm = HomeViewModel(loadDashboard: StubDashboardUseCase(result: .success(dashboard)))
        #expect(vm.offlineSummary == nil)
        await vm.load()
        #expect(vm.offlineSummary == "1 of 2 offline")
        #expect(vm.religionName(for: "r1") == "R1")
        #expect(vm.religionName(for: "missing") == nil)
    }
}
