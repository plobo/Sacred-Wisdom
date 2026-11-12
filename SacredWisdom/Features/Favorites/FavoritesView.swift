import SwiftUI

/// Screen 9: saved passages, custom collections, notes, search and removal.
struct FavoritesView: View {
    @State var viewModel: FavoritesViewModel

    @State private var isNamingCollection = false
    @State private var newCollectionName = ""
    @State private var renaming: BookmarkCollection?
    @State private var renameText = ""
    @State private var deleting: BookmarkCollection?

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingStateView()
            case .failed(let message):
                ErrorStateView(message: message) { Task { await viewModel.load() } }
            case .loaded:
                if viewModel.hasBookmarks {
                    list
                } else {
                    ScrollView {
                        EmptyStateView(systemImage: "bookmark", title: "No saved passages",
                                       message: "Tap the bookmark on any passage to save it here, with your own notes.")
                            .padding(.top, SWSpacing.xxl)
                    }
                }
            }
        }
        .swScreenBackground()
        .navigationTitle("Favorites")
        .accessibilityIdentifier("screen.favorites")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newCollectionName = ""
                    isNamingCollection = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel(Text("New Collection"))
                .accessibilityIdentifier("favorites.newCollection")
            }
        }
        .alert("New Collection", isPresented: $isNamingCollection) {
            TextField("Name", text: $newCollectionName)
                .accessibilityIdentifier("newCollection.name")
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newCollectionName
                Task { await viewModel.createCollection(named: name) }
            }
            .accessibilityIdentifier("newCollection.create")
        }
        .alert("Rename Collection", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let id = renaming?.id {
                    let name = renameText
                    Task { await viewModel.renameCollection(id, to: name) }
                }
            }
        }
        .confirmationDialog(
            "Delete collection?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { collection in
            Button("Delete “\(collection.name)”", role: .destructive) {
                Task { await viewModel.deleteCollection(collection.id) }
            }
        } message: { _ in
            Text("Its passages stay saved and become unfiled.")
        }
        .confirmationDialog(
            "Remove bookmark and note?",
            isPresented: Binding(get: { viewModel.pendingRemoval != nil }, set: { if !$0 { viewModel.cancelRemoval() } }),
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
        .task(id: viewModel.bookmarksRevision) { await viewModel.load() }
    }

    private var list: some View {
        List {
            Section {
                CollectionFilterBar(
                    collections: viewModel.collections,
                    selection: viewModel.filter,
                    onSelect: viewModel.select,
                    onRename: { collection in
                        renameText = collection.name
                        renaming = collection
                    },
                    onDelete: { deleting = $0 }
                )
                .listRowInsets(EdgeInsets(top: SWSpacing.s, leading: 0, bottom: SWSpacing.s, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            Section {
                if viewModel.visibleItems.isEmpty {
                    EmptyStateView(systemImage: "magnifyingglass", title: "Nothing here",
                                   message: viewModel.searchText.isEmpty
                                       ? "No saved passages in this collection yet."
                                       : "No saved passages match your search.")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(viewModel.visibleItems) { item in
                    FavoriteRow(item: item, collectionName: viewModel.collectionName(for: item))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: SWSpacing.xs, leading: SWSpacing.l, bottom: SWSpacing.xs, trailing: SWSpacing.l))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { Task { await viewModel.remove(item) } } label: {
                                Label("Remove", systemImage: "bookmark.slash")
                            }
                        }
                        .contextMenu {
                            Menu("Move to Collection", systemImage: "folder") {
                                Button("Unfiled") { Task { await viewModel.move(item, to: nil) } }
                                ForEach(viewModel.collections) { collection in
                                    Button(collection.name) { Task { await viewModel.move(item, to: collection.id) } }
                                }
                            }
                            Button("Remove Bookmark", systemImage: "bookmark.slash", role: .destructive) {
                                Task { await viewModel.remove(item) }
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $viewModel.searchText, prompt: "Search saved passages and notes")
    }
}

private struct CollectionFilterBar: View {
    let collections: [BookmarkCollection]
    let selection: FavoritesViewModel.CollectionFilter
    let onSelect: (FavoritesViewModel.CollectionFilter) -> Void
    let onRename: (BookmarkCollection) -> Void
    let onDelete: (BookmarkCollection) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SWSpacing.s) {
                FilterChip(title: String(localized: "All"), isSelected: selection == .all) { onSelect(.all) }
                    .accessibilityIdentifier("favorites.filter.all")
                FilterChip(title: String(localized: "Unfiled"), isSelected: selection == .unfiled) { onSelect(.unfiled) }
                    .accessibilityIdentifier("favorites.filter.unfiled")
                ForEach(collections) { collection in
                    FilterChip(title: collection.name, isSelected: selection == .collection(collection.id)) {
                        onSelect(.collection(collection.id))
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { onRename(collection) }
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(collection) }
                    }
                    .accessibilityIdentifier("favorites.filter.\(collection.name)")
                    .accessibilityHint(Text("Touch and hold to rename or delete"))
                }
            }
            .padding(.horizontal, SWSpacing.l)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Collections"))
    }
}

private struct FavoriteRow: View {
    let item: FavoriteItem
    let collectionName: String?

    var body: some View {
        Group {
            if let passage = item.passage {
                // A hidden link keeps List from drawing its own disclosure chevron beside the card.
                card(passage)
                    .background {
                        NavigationLink(value: AppRoute.passageDetail(passage.id)) { EmptyView() }.opacity(0)
                    }
            } else {
                SWCard {
                    VStack(alignment: .leading, spacing: SWSpacing.xs) {
                        Text("Passage unavailable")
                            .font(SWTypography.headline)
                            .foregroundStyle(SWColors.textPrimary)
                        Text("This passage is not in the installed library. Swipe to remove the bookmark.")
                            .font(SWTypography.caption)
                            .foregroundStyle(SWColors.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("favorite.\(item.bookmark.passageID)")
            }
        }
    }

    private func card(_ passage: ScripturePassage) -> some View {
        SWCard {
            VStack(alignment: .leading, spacing: SWSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(passage.reference)
                        .font(SWTypography.reference)
                        .foregroundStyle(SWColors.primary)
                    Spacer()
                    if let religion = item.religion {
                        Text(religion.name)
                            .font(SWTypography.caption)
                            .foregroundStyle(SWColors.secondary)
                    }
                }
                if let text = passage.texts.first {
                    Text(text.text)
                        .font(SWTypography.scripture)
                        .foregroundStyle(SWColors.textPrimary)
                        .lineLimit(3)
                        .scriptureDirection(text.translation.languageCode)
                }
                if let note = item.bookmark.note {
                    Label(note, systemImage: "note.text")
                        .font(SWTypography.caption)
                        .foregroundStyle(SWColors.textSecondary)
                        .lineLimit(2)
                }
                if let collectionName {
                    Label(collectionName, systemImage: "folder")
                        .font(SWTypography.caption.weight(.semibold))
                        .foregroundStyle(SWColors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("favorite.\(item.bookmark.passageID)")
    }
}
