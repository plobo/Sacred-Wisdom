import Foundation
import SwiftData

/// SwiftData model for a past search. User data only; never mixed with scripture content.
@Model
final class SearchHistoryEntry {
    @Attribute(.unique) var id: UUID
    var query: String
    /// Folded form used to de-duplicate ("Mercy" and "mercy " are one entry).
    @Attribute(.unique) var normalizedQuery: String
    var searchedAt: Date

    init(id: UUID = UUID(), query: String, normalizedQuery: String, searchedAt: Date) {
        self.id = id
        self.query = query
        self.normalizedQuery = normalizedQuery
        self.searchedAt = searchedAt
    }
}
