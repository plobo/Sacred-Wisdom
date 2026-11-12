import Foundation
import Observation

enum AppTab: Hashable, CaseIterable, Sendable {
    case home, search, favorites, library, settings
}

enum AppRoute: Hashable {
    case religion(ReligionSummary)
    case collection(String)
    /// `translationID` opens the reader in that translation (e.g. the one a search matched).
    case reader(ReaderStart, translationID: String? = nil)
    /// Verse Details. `translationID` puts that translation first (e.g. the one a search matched).
    case passageDetail(String, translationID: String? = nil)
    case askQuestion
    case offlineContent
    case attributions
}

/// Owns navigation state: the selected tab and one navigation stack per tab.
@Observable
@MainActor
final class AppCoordinator {
    var selectedTab: AppTab = .home
    var paths: [AppTab: [AppRoute]] = [:]
    /// Incremented to ask the Search tab to focus its search field.
    private(set) var searchActivationRequest = 0
    /// A search the Search tab should run (from Siri or Shortcuts). Each request has a new ID.
    private(set) var pendingSearch: SearchRequest?

    struct SearchRequest: Equatable {
        let id: UUID
        let query: String
    }

    func select(_ tab: AppTab) {
        selectedTab = tab
    }

    func push(_ route: AppRoute, in tab: AppTab) {
        paths[tab, default: []].append(route)
        selectedTab = tab
    }

    func activateSearch() {
        selectedTab = .search
        searchActivationRequest += 1
    }

    /// Opens Verse Details for a passage on the Home tab, replacing whatever was stacked there.
    func openPassage(_ passageID: String) {
        paths[.home] = [.passageDetail(passageID)]
        selectedTab = .home
    }

    /// Switches to Search and runs the query there.
    func showSearchResults(for query: String) {
        paths[.search] = []
        pendingSearch = SearchRequest(id: UUID(), query: query)
        selectedTab = .search
    }

    /// Called by the Search tab once it has started the requested search.
    func consumePendingSearch(_ id: UUID) {
        if pendingSearch?.id == id { pendingSearch = nil }
    }

    func popToRoot(_ tab: AppTab) {
        paths[tab] = []
    }
}
