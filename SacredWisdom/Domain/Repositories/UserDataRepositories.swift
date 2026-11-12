import Foundation

protocol BookmarkRepository: Sendable {
    /// Newest first.
    func bookmarks() async throws(AppError) -> [Bookmark]
    func bookmark(passageID: String) async throws(AppError) -> Bookmark?
    func bookmarkedPassageIDs() async throws(AppError) -> Set<String>
    /// Idempotent: bookmarking an already-saved passage keeps the original bookmark.
    @discardableResult
    func addBookmark(passageID: String, at date: Date) async throws(AppError) -> Bookmark
    /// Removes the bookmark and its note.
    func removeBookmark(passageID: String) async throws(AppError)
    /// Saves a note, bookmarking the passage if needed. An empty note clears it but keeps the bookmark.
    @discardableResult
    func setNote(_ note: String, passageID: String, at date: Date) async throws(AppError) -> Bookmark
    /// Files a bookmark in a collection (nil = unfiled).
    func moveBookmark(passageID: String, toCollection collectionID: UUID?) async throws(AppError)

    /// Oldest first.
    func collections() async throws(AppError) -> [BookmarkCollection]
    /// Creates a collection; a name matching an existing one (ignoring case and spacing) returns that collection.
    @discardableResult
    func createCollection(named name: String, at date: Date) async throws(AppError) -> BookmarkCollection
    func renameCollection(id: UUID, to name: String) async throws(AppError)
    /// Deletes the collection; its bookmarks are kept and become unfiled.
    func deleteCollection(id: UUID) async throws(AppError)
}

protocol ReadingHistoryRepository: Sendable {
    /// Records a view. Each passage appears once; viewing it again moves it to the top.
    func record(passageID: String, at date: Date) async throws(AppError)
    /// Newest first.
    func recent(limit: Int) async throws(AppError) -> [ReadingHistoryItem]
    func clear() async throws(AppError)
}
