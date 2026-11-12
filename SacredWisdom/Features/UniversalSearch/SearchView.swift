import SwiftUI

/// Screens 5 and 6: universal search and grouped results.
struct SearchView: View {
    @State var viewModel: SearchViewModel
    let coordinator: AppCoordinator
    let makeVoiceSearch: () -> VoiceSearchViewModel

    @State private var voiceSearch: VoiceSearchViewModel?

    @State private var text = ""
    @State private var isSearchPresented = false
    @State private var showFilters = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SWSpacing.l) {
                if let options = viewModel.filterOptions {
                    ReligionFilterBar(religions: options.religions, isSelected: viewModel.isReligionSelected) { id in
                        Task { await viewModel.toggleReligion(id) }
                    }
                }
                content
            }
            .padding(SWSpacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .swScreenBackground()
        .accessibilityIdentifier("screen.search")
        .navigationTitle("Search")
        .searchable(text: $text, isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .always), prompt: "Search all sacred texts")
        .searchSuggestions {
            ForEach(viewModel.completions, id: \.self) { completion in
                Text(completion).searchCompletion(completion)
            }
        }
        .onSubmit(of: .search) { Task { await viewModel.submit() } }
        .onChange(of: text) { _, newValue in viewModel.queryChanged(newValue) }
        .onChange(of: coordinator.searchActivationRequest) { isSearchPresented = true }
        .onChange(of: coordinator.pendingSearch) { runPendingSearch() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { voiceSearch = makeVoiceSearch() } label: {
                    Image(systemName: "mic")
                }
                .accessibilityLabel(Text("Search by Voice"))
                .accessibilityIdentifier("search.voice")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showFilters = true } label: {
                    Image(systemName: viewModel.filters.languageCodes.isEmpty && viewModel.filters.translationIDs.isEmpty
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel(Text("Filters"))
                .accessibilityIdentifier("search.filtersButton")
                .disabled(viewModel.filterOptions == nil)
            }
        }
        .sheet(item: $voiceSearch) { voice in
            VoiceSearchSheet(viewModel: voice) { transcript in select(transcript) }
        }
        .sheet(isPresented: $showFilters) {
            if let options = viewModel.filterOptions {
                SearchFiltersSheet(viewModel: viewModel, options: options)
            }
        }
        .task(id: viewModel.bookmarksRevision) { await viewModel.refreshBookmarks() }
        .confirmationDialog(
            "Remove bookmark and note?",
            isPresented: Binding(get: { viewModel.pendingRemovalID != nil }, set: { if !$0 { viewModel.cancelRemoval() } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { Task { await viewModel.confirmRemoval() } }
                .accessibilityIdentifier("bookmark.confirmRemove")
        } message: {
            Text("Your note on this passage will be deleted too.")
        }
        .alert(
            "Couldn’t Save",
            isPresented: Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } }),
            presenting: viewModel.actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .task {
            await viewModel.onAppear()
            if coordinator.searchActivationRequest > 0 { isSearchPresented = true }
            runPendingSearch()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            SearchIdleContent(
                recent: viewModel.recent,
                suggestions: viewModel.suggestedQuestions,
                onSelect: select,
                onRemove: { id in Task { await viewModel.removeRecent(id) } },
                onClear: { Task { await viewModel.clearRecent() } }
            )
        case .searching:
            LoadingStateView(message: "Searching all traditions…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await viewModel.submit() } }
        case .empty:
            VStack(spacing: SWSpacing.m) {
                EmptyStateView(systemImage: "text.magnifyingglass", title: "No passages found",
                               message: "Try different words, or put an exact phrase in quotes.")
                if !viewModel.filters.isEmpty {
                    Button("Clear Filters") { Task { await viewModel.clearFilters() } }
                        .buttonStyle(.bordered)
                        .tint(SWColors.primary)
                        .accessibilityIdentifier("search.clearFilters")
                }
            }
        case .results(let results):
            SearchResultsContent(
                results: results,
                isBookmarked: viewModel.isBookmarked,
                onToggleBookmark: { id in Task { await viewModel.toggleBookmark(id) } }
            )
        }
    }

    /// Runs a search requested from outside the screen (Siri, Shortcuts, voice input).
    private func runPendingSearch() {
        guard let request = coordinator.pendingSearch else { return }
        coordinator.consumePendingSearch(request.id)
        select(request.query)
    }

    private func select(_ query: String) {
        text = query
        isSearchPresented = false
        Task { await viewModel.select(query) }
    }
}

private struct ReligionFilterBar: View {
    let religions: [Religion]
    let isSelected: (String) -> Bool
    let onToggle: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SWSpacing.s) {
                ForEach(religions) { religion in
                    FilterChip(title: religion.name, emblem: religion.emblem, isSelected: isSelected(religion.id)) {
                        onToggle(religion.id)
                    }
                    .accessibilityIdentifier("filter.religion.\(religion.id)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Filter by tradition"))
    }
}
