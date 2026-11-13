import SwiftUI

/// Screen 7: Verse Details.
struct PassageDetailView: View {
    @State var viewModel: PassageDetailViewModel

    @State private var isEditingNote = false
    @State private var isNamingCollection = false
    @State private var newCollectionName = ""

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingStateView()
            case .failed(let message):
                ErrorStateView(message: message) { Task { await viewModel.load() } }
            case .loaded(let detail):
                ScrollView {
                    content(detail)
                        .padding(SWSpacing.l)
                }
                // On the scroll view, not the container, so child identifiers survive.
                .accessibilityIdentifier("screen.passageDetail")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let audio = viewModel.audio, audio.status != .idle {
                        VStack(spacing: 0) {
                            Divider()
                            AudioPlayerBar(
                                controller: audio,
                                translationChoices: viewModel.audioTranslationChoices,
                                selectedTranslationID: viewModel.audioTranslationID,
                                onSelectTranslation: { id in Task { await viewModel.selectAudioTranslation(id) } }
                            )
                            .padding(.horizontal, SWSpacing.l)
                            .padding(.vertical, SWSpacing.s)
                        }
                        .background(.bar)
                    }
                }
                .navigationTitle(detail.passage.reference)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
            }
        }
        .swScreenBackground()
        .bookmarkAlerts(viewModel.bookmarks)
        .sheet(isPresented: $isEditingNote) {
            NoteEditorSheet(reference: viewModel.detail?.passage.reference ?? "",
                            initialText: viewModel.bookmarks.note ?? "") { text in
                Task { await viewModel.bookmarks.saveNote(text) }
            }
        }
        .alert("New Collection", isPresented: $isNamingCollection) {
            TextField("Name", text: $newCollectionName)
                .accessibilityIdentifier("newCollection.name")
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newCollectionName
                Task { await viewModel.bookmarks.createCollectionAndMove(named: name) }
            }
            .accessibilityIdentifier("newCollection.create")
        } message: {
            Text("The passage will be bookmarked and filed in this collection.")
        }
        .task { if viewModel.state == .idle { await viewModel.load() } }
        .onDisappear { viewModel.stopListening() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let shareText = viewModel.shareText, let detail = viewModel.detail {
                ShareLink(item: shareText, subject: Text(detail.passage.reference),
                          preview: SharePreview(detail.passage.reference)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(Text("Share"))
                .accessibilityIdentifier("detail.share")
            }
            BookmarkToggleButton(controller: viewModel.bookmarks, identifier: "detail.bookmark")
        }
    }

    @ViewBuilder
    private func content(_ detail: PassageDetail) -> some View {
        VStack(alignment: .leading, spacing: SWSpacing.l) {
            DetailHeader(detail: detail)
            if let original = detail.passage.originalText {
                OriginalTextBlock(text: original, languageName: viewModel.originalLanguageName,
                                  isRightToLeft: viewModel.isOriginalRightToLeft, fontScale: 1,
                                  identifier: "detail.originalText")
            }
            ForEach(viewModel.orderedTexts, id: \.translation.id) { text in
                TranslationTextBlock(text: text, fontScale: 1, identifier: "detail.translation.\(text.translation.id)")
            }
            DetailAttribution(passage: detail.passage, texts: viewModel.orderedTexts)
            NavigationLink(value: AppRoute.reader(.passage(detail.passage.id), translationID: viewModel.primaryTranslationID)) {
                Label("Read in Context", systemImage: "book")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
                .foregroundStyle(SWColors.onPrimary)
            .tint(SWColors.primary)
            .accessibilityIdentifier("detail.readInContext")
            DetailNoteSection(
                note: viewModel.bookmarks.note,
                isBookmarked: viewModel.bookmarks.isBookmarked,
                collectionName: viewModel.bookmarks.collectionName,
                collections: viewModel.bookmarks.collections,
                onEditNote: { isEditingNote = true },
                onMove: { id in Task { await viewModel.bookmarks.move(toCollection: id) } },
                onNewCollection: {
                    newCollectionName = ""
                    isNamingCollection = true
                }
            )
            DetailContextSection(detail: detail, originalLanguageName: viewModel.originalLanguageName)
            RelatedPassagesSection(related: detail.related)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
