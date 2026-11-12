import Foundation
import Observation

/// Screen 9: saved passages, custom collections, notes, search within saved passages.
@Observable
@MainActor
final class FavoritesViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(FavoritesContent)
        case failed(String)
    }

    enum CollectionFilter: Hashable {
        case all
        case unfiled
        case collection(UUID)
    }

    private(set) var state: State = .idle
    private(set) var filter: CollectionFilter = .all
    var searchText = ""
    /// A bookmark whose removal would delete a note; the view asks for confirmation.
    private(set) var pendingRemoval: FavoriteItem?
    var actionError: String?

    private let loadFavorites: any LoadFavoritesUseCaseProtocol
    private let userData: UserDataContext

    init(loadFavorites: any LoadFavoritesUseCaseProtocol, userData: UserDataContext) {
        self.loadFavorites = loadFavorites
        self.userData = userData
    }

    var bookmarksRevision: Int { userData.changes.bookmarks }

    // MARK: Loading

    func load() async {
        if case .loading = state { return }
        if case .loaded = state {
            await reload()
            return
        }
        state = .loading
        await reload()
    }

    private func reload() async {
        do {
            let content = try await loadFavorites.execute()
            if case .collection(let id) = filter, !content.collections.contains(where: { $0.id == id }) {
                filter = .all
            }
            state = .loaded(content)
        } catch {
            state = .failed(error.userMessage)
        }
    }

    // MARK: Filtering

    var content: FavoritesContent? {
        guard case .loaded(let content) = state else { return nil }
        return content
    }

    var collections: [BookmarkCollection] { content?.collections ?? [] }
    var hasBookmarks: Bool { !(content?.items.isEmpty ?? true) }

    func select(_ filter: CollectionFilter) {
        self.filter = filter
    }

    /// Items in the selected collection where every search word starts a word of the reference, text, note,
    /// tradition or collection name (case-, accent- and Arabic/Hebrew-mark-insensitive).
    var visibleItems: [FavoriteItem] {
        guard let content else { return [] }
        let inCollection = content.items.filter { item in
            switch filter {
            case .all: true
            case .unfiled: item.bookmark.collectionID == nil
            case .collection(let id): item.bookmark.collectionID == id
            }
        }
        let words = Self.searchWords(searchText)
        guard !words.isEmpty else { return inCollection }
        return inCollection.filter { item in
            let haystack = Self.searchWords(searchableText(item, collections: content.collections))
            return words.allSatisfy { word in haystack.contains { $0.hasPrefix(word) } }
        }
    }

    func collectionName(for item: FavoriteItem) -> String? {
        guard let id = item.bookmark.collectionID else { return nil }
        return collections.first { $0.id == id }?.name
    }

    private static func searchWords(_ text: String) -> [String] {
        SearchTextNormalizer.words(in: SearchTextNormalizer.normalize(text).folding(options: .diacriticInsensitive, locale: nil))
    }

    private func searchableText(_ item: FavoriteItem, collections: [BookmarkCollection]) -> String {
        var parts = [item.bookmark.note ?? "", item.religion?.name ?? "", collectionName(for: item) ?? ""]
        if let passage = item.passage {
            parts += [passage.reference, passage.originalText ?? ""] + passage.texts.map(\.text)
        }
        return parts.joined(separator: " ")
    }

    // MARK: Editing

    func remove(_ item: FavoriteItem) async {
        if item.bookmark.note != nil {
            pendingRemoval = item
        } else {
            await performRemoval(item)
        }
    }

    func confirmRemoval() async {
        guard let item = pendingRemoval else { return }
        pendingRemoval = nil
        await performRemoval(item)
    }

    func cancelRemoval() {
        pendingRemoval = nil
    }

    private func performRemoval(_ item: FavoriteItem) async {
        await perform { [userData] () async throws(AppError) in
            try await userData.bookmarks.removeBookmark(passageID: item.bookmark.passageID)
        }
    }

    func move(_ item: FavoriteItem, to collectionID: UUID?) async {
        await perform { [userData] () async throws(AppError) in
            try await userData.bookmarks.moveBookmark(passageID: item.bookmark.passageID, toCollection: collectionID)
        }
    }

    func createCollection(named name: String) async {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var created: BookmarkCollection?
        await perform { [userData] () async throws(AppError) in
            created = try await userData.bookmarks.createCollection(named: name, at: userData.now())
        }
        if let created { filter = .collection(created.id) }
    }

    func renameCollection(_ id: UUID, to name: String) async {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await perform { [userData] () async throws(AppError) in
            try await userData.bookmarks.renameCollection(id: id, to: name)
        }
    }

    func deleteCollection(_ id: UUID) async {
        await perform { [userData] () async throws(AppError) in
            try await userData.bookmarks.deleteCollection(id: id)
        }
    }

    private func perform(_ write: @MainActor () async throws(AppError) -> Void) async {
        do {
            try await write()
        } catch {
            actionError = error.userMessage
        }
        userData.changes.bookmarksChanged()
        await reload()
    }
}
