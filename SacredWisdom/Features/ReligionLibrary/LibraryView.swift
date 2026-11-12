import SwiftUI

/// Library tab: lists all six traditions with equal prominence.
struct LibraryView: View {
    @State var viewModel: LibraryViewModel
    let coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: SWSpacing.m) {
                switch viewModel.state {
                case .idle, .loading:
                    LoadingStateView()
                case .failed(let message):
                    ErrorStateView(message: message) { Task { await viewModel.load() } }
                case .loaded(let summaries) where summaries.isEmpty:
                    EmptyStateView(systemImage: "books.vertical", title: "No collections", message: "Collections will appear here once content is installed.")
                case .loaded(let summaries):
                    ForEach(summaries) { summary in
                        Button { coordinator.push(.religion(summary), in: .library) } label: {
                            ReligionCard(summary: summary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(SWSpacing.l)
        }
        .swScreenBackground()
        .navigationTitle("Library")
        .accessibilityIdentifier("screen.library")
        .task { if viewModel.state == .idle { await viewModel.load() } }
        .task(id: viewModel.contentRevision) { await viewModel.refresh() }
    }
}
