import Foundation

/// A saved passage. User data: lives in SwiftData, never in the scripture database.
struct Bookmark: Identifiable, Hashable, Sendable {
    let id: UUID
    let passageID: String
    let createdAt: Date
    /// The user's personal note, if any. Notes are stored with the bookmark.
    let note: String?
    let noteUpdatedAt: Date?
    /// The user collection this bookmark is filed in; nil means unfiled.
    let collectionID: UUID?
}

/// A user-created group of bookmarks ("custom collection").
struct BookmarkCollection: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
}

struct ReadingHistoryItem: Hashable, Sendable {
    let passageID: String
    let viewedAt: Date
}
