import Testing
@testable import SacredWisdom

@MainActor
@Suite struct AppCoordinatorTests {
    @Test func pushSelectsTabAndAppendsRoute() {
        let coordinator = AppCoordinator()
        coordinator.push(.askQuestion, in: .library)
        #expect(coordinator.selectedTab == .library)
        #expect(coordinator.paths[.library] == [.askQuestion])
        #expect(coordinator.paths[.home] == nil)
    }

    @Test func popToRootClearsOnlyThatTab() {
        let coordinator = AppCoordinator()
        coordinator.push(.askQuestion, in: .home)
        coordinator.push(.askQuestion, in: .library)
        coordinator.popToRoot(.home)
        #expect(coordinator.paths[.home] == [])
        #expect(coordinator.paths[.library] == [.askQuestion])
    }
}
