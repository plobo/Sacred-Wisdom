import Foundation
import SwiftData

/// A saved passage, with the user's optional note. References scripture only by stable passage ID.
@Model
final class UserBookmark {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var passageID: String
    var createdAt: Date
    var note: String?
    var noteUpdatedAt: Date?
    /// `UserCollection.id`, or nil when unfiled.
    var customCollectionID: UUID?

    init(id: UUID = UUID(), passageID: String, createdAt: Date) {
        self.id = id
        self.passageID = passageID
        self.createdAt = createdAt
    }
}

/// A user-defined group of bookmarks.
@Model
final class UserCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// The most recent view of a passage. One row per passage.
@Model
final class ReadingHistoryEntry {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var passageID: String
    var viewedAt: Date

    init(id: UUID = UUID(), passageID: String, viewedAt: Date) {
        self.id = id
        self.passageID = passageID
        self.viewedAt = viewedAt
    }
}
