import Foundation
import SwiftData

/// Builds the SwiftData container for user data: search history, bookmarks and notes, collections, reading history.
/// Scripture never lives here; user records reference it by stable passage ID.
enum PersistenceManager {
    enum Location: Sendable, Equatable {
        case inMemory
        /// SwiftData's default store in Application Support.
        case defaultFile
        case file(URL)
    }

    static let models: [any PersistentModel.Type] = [
        SearchHistoryEntry.self, UserBookmark.self, UserCollection.self, ReadingHistoryEntry.self,
    ]

    static func makeContainer(location: Location) throws(AppError) -> ModelContainer {
        do {
            let configuration = switch location {
            case .inMemory: ModelConfiguration(isStoredInMemoryOnly: true)
            case .defaultFile: ModelConfiguration(isStoredInMemoryOnly: false)
            case .file(let url): ModelConfiguration(url: url)
            }
            return try ModelContainer(for: Schema(models), configurations: configuration)
        } catch {
            throw .database("User data store: \(error)")
        }
    }

    /// Deletes a file store and its SQLite sidecar files. Used by UI tests to start from a clean slate.
    static func deleteStore(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
}
