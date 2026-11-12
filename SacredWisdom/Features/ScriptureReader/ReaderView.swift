import SwiftUI

/// Screen 4: reads one passage at a time with previous/next navigation.
struct ReaderView: View {
    @State var viewModel: ReaderViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingStateView()
            case .failed(let message):
                ErrorStateView(message: message) { Task { await viewModel.load() } }
            case .loaded(let page):
                ScrollView {
                    ReaderPassageContent(
                        page: page,
                        text: viewModel.displayedText,
                        fontScale: viewModel.fontScale,
                        isOriginalRightToLeft: viewModel.isOriginalRightToLeft,
                        originalLanguageName: viewModel.originalLanguageName
                    )
                    .padding(SWSpacing.l)
                    .id(page.passage.id)
                }
                // Identifier lives on the scroll view: on the outer container it would
                // override the identifiers of the navigation bar's buttons.
                .accessibilityIdentifier("screen.reader")
                .safeAreaInset(edge: .bottom) {
                    ReaderNavigationBar(
                        reference: page.passage.reference,
                        canGoPrevious: viewModel.canGoPrevious,
                        canGoNext: viewModel.canGoNext,
                        onPrevious: { Task { await viewModel.goToPrevious() } },
                        onNext: { Task { await viewModel.goToNext() } }
                    )
                }
                .navigationTitle(page.collection.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar(page) }
            }
        }
        .swScreenBackground()
        .bookmarkAlerts(viewModel.bookmarks)
        .task { if viewModel.state == .idle { await viewModel.load() } }
    }

    @ToolbarContentBuilder
    private func toolbar(_ page: ReaderPage) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink(value: AppRoute.passageDetail(page.passage.id, translationID: viewModel.selectedTranslationID)) {
                Image(systemName: "info.circle")
            }
            .accessibilityLabel(Text("Passage Details"))
            .accessibilityIdentifier("reader.details")
            BookmarkToggleButton(controller: viewModel.bookmarks, identifier: "reader.bookmark")
            if viewModel.hasTranslationChoice {
                TranslationMenu(
                    translations: page.translations,
                    selectedID: viewModel.selectedTranslationID
                ) { id in Task { await viewModel.selectTranslation(id) } }
            }
            FontSizeMenu(
                canDecrease: viewModel.canDecreaseFontSize,
                canIncrease: viewModel.canIncreaseFontSize,
                onDecrease: viewModel.decreaseFontSize,
                onIncrease: viewModel.increaseFontSize
            )
        }
    }
}
