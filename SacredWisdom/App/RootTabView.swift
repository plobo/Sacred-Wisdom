import SwiftUI

struct RootTabView: View {
    let dependencies: AppDependencies
    @Bindable var coordinator: AppCoordinator

    @State private var homeViewModel: HomeViewModel
    @State private var libraryViewModel: LibraryViewModel
    @State private var searchViewModel: SearchViewModel
    @State private var favoritesViewModel: FavoritesViewModel
    @State private var settingsViewModel: SettingsViewModel

    init(dependencies: AppDependencies, coordinator: AppCoordinator) {
        self.dependencies = dependencies
        self.coordinator = coordinator
        _homeViewModel = State(initialValue: dependencies.makeHomeViewModel())
        _libraryViewModel = State(initialValue: dependencies.makeLibraryViewModel())
        _searchViewModel = State(initialValue: dependencies.makeSearchViewModel())
        _favoritesViewModel = State(initialValue: dependencies.makeFavoritesViewModel())
        _settingsViewModel = State(initialValue: dependencies.makeSettingsViewModel())
    }

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            stack(.home) { HomeView(viewModel: homeViewModel, coordinator: coordinator) }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
                .accessibilityIdentifier("tab.home")
            stack(.search) { SearchView(viewModel: searchViewModel, coordinator: coordinator, makeVoiceSearch: dependencies.makeVoiceSearchViewModel) }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
                .accessibilityIdentifier("tab.search")
            stack(.favorites) { FavoritesView(viewModel: favoritesViewModel) }
                .tabItem { Label("Favorites", systemImage: "bookmark.fill") }
                .tag(AppTab.favorites)
                .accessibilityIdentifier("tab.favorites")
            stack(.library) { LibraryView(viewModel: libraryViewModel, coordinator: coordinator) }
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                .tag(AppTab.library)
                .accessibilityIdentifier("tab.library")
            stack(.settings) { SettingsView(configuration: dependencies.configuration, viewModel: settingsViewModel) }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
                .accessibilityIdentifier("tab.settings")
        }
        .tint(SWColors.primary)
    }

    private func stack<Root: View>(_ tab: AppTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: Binding(
            get: { coordinator.paths[tab] ?? [] },
            set: { coordinator.paths[tab] = $0 }
        )) {
            root()
                .navigationDestination(for: AppRoute.self, destination: destination)
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .religion(let summary):
            ReligionLibraryView(summary: summary)
        case .collection(let collectionID):
            CollectionBrowserView(viewModel: dependencies.makeCollectionBrowserViewModel(collectionID: collectionID))
        case .reader(let start, let translationID):
            ReaderView(viewModel: dependencies.makeReaderViewModel(start: start, translationID: translationID))
        case .passageDetail(let passageID, let translationID):
            PassageDetailView(viewModel: dependencies.makePassageDetailViewModel(passageID: passageID, translationID: translationID))
        case .attributions:
            AttributionsView(load: LoadAttributionsUseCase(scripture: dependencies.library))
        case .offlineContent:
            OfflineContentView(manager: dependencies.downloads)
        case .askQuestion:
            AskQuestionView(viewModel: dependencies.makeAskQuestionViewModel(),
                            makeVoiceSearch: dependencies.makeVoiceSearchViewModel)
        }
    }
}
