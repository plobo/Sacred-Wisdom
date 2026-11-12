import Foundation
import Observation

/// Revision counters for user data. View models bump them after writing; screens that show the same data
/// elsewhere (Favorites, Home, open details) observe them and reload.
@Observable
@MainActor
final class UserDataChanges {
    private(set) var bookmarks = 0
    private(set) var readingHistory = 0
    /// Installed scripture changed (a package was downloaded or removed).
    private(set) var content = 0

    func bookmarksChanged() { bookmarks += 1 }
    func readingHistoryChanged() { readingHistory += 1 }
    func contentChanged() { content += 1 }
}

/// What a view model needs to read and write user data, bundled so feature initializers stay small.
@MainActor
struct UserDataContext {
    let bookmarks: any BookmarkRepository
    let history: any ReadingHistoryRepository
    let changes: UserDataChanges
    let now: @Sendable () -> Date

    init(
        bookmarks: any BookmarkRepository,
        history: any ReadingHistoryRepository,
        changes: UserDataChanges,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.bookmarks = bookmarks
        self.history = history
        self.changes = changes
        self.now = now
    }

    /// No persistence: reads are empty and writes fail. Default for view models under test that ignore user data.
    static func unavailable() -> UserDataContext {
        let store = UnavailableUserDataRepository()
        return UserDataContext(bookmarks: store, history: store, changes: UserDataChanges())
    }

    /// Records that a passage was viewed. Failures are ignored: history is a convenience, never a blocker.
    func recordView(of passageID: String) async {
        do {
            try await history.record(passageID: passageID, at: now())
            changes.readingHistoryChanged()
        } catch {
            Log.userData.error("Recording reading history failed: \(String(describing: error), privacy: .public)")
        }
    }
}
