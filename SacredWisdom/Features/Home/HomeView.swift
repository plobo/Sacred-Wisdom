import SwiftUI

struct HomeView: View {
    @State var viewModel: HomeViewModel
    let coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SWSpacing.xl) {
                HomeHeader(greeting: viewModel.greeting)
                SearchBarButton(placeholder: "Search all sacred texts") {
                    coordinator.activateSearch()
                }
                .accessibilityIdentifier("home.searchBar")
                content
            }
            .padding(SWSpacing.l)
        }
        .swScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("screen.home")
        .task { if viewModel.state == .idle { await viewModel.load() } }
        .task(id: viewModel.readingHistoryRevision) { await viewModel.refresh() }
        .task(id: viewModel.contentRevision) { await viewModel.refresh() }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView()
        case .failed(let message):
            ErrorStateView(message: message) { Task { await viewModel.load() } }
        case .loaded(let dashboard):
            HomeCollectionsSection(
                religions: dashboard.religions,
                offlineSummary: viewModel.offlineSummary
            ) { coordinator.push(.religion($0), in: .home) }
            HomeDailyPassageSection(
                passage: dashboard.dailyPassage,
                religionName: dashboard.dailyPassage.flatMap { viewModel.religionName(for: $0.religionID) }
            )
            HomeAskCard { coordinator.push(.askQuestion, in: .home) }
            HomeRecentSection(passages: dashboard.recentPassages, religionName: viewModel.religionName(for:))
        }
    }
}
