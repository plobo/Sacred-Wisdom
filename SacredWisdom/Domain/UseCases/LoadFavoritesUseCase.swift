import Foundation

/// One saved passage, joined with its scripture. `passage` is nil when the content is no longer installed.
struct FavoriteItem: Identifiable, Hashable, Sendable {
    let bookmark: Bookmark
    let passage: ScripturePassage?
    let religion: Religion?

    var id: String { bookmark.passageID }
}

struct FavoritesContent: Equatable, Sendable {
    let items: [FavoriteItem]
    let collections: [BookmarkCollection]
}

protocol LoadFavoritesUseCaseProtocol: Sendable {
    func execute() async throws(AppError) -> FavoritesContent
}

struct LoadFavoritesUseCase: LoadFavoritesUseCaseProtocol {
    let bookmarks: any BookmarkRepository
    let scripture: any ScriptureRepository & ReligionRepository

    func execute() async throws(AppError) -> FavoritesContent {
        let saved = try await bookmarks.bookmarks()
        let collections = try await bookmarks.collections()
        let religions = Dictionary(uniqueKeysWithValues: try await scripture.fetchReligions().map { ($0.id, $0) })
        var items: [FavoriteItem] = []
        for bookmark in saved {
            var passage: ScripturePassage?
            do throws(AppError) {
                passage = try await scripture.passage(id: bookmark.passageID)
            } catch .contentNotFound {
                passage = nil
            }
            items.append(FavoriteItem(bookmark: bookmark, passage: passage, religion: passage.flatMap { religions[$0.religionID] }))
        }
        return FavoritesContent(items: items, collections: collections)
    }
}
