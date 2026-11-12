import Foundation
import Observation

/// Bookmark, note and collection state for the passage on screen. Shared by the reader and Verse Details.
@Observable
@MainActor
final class PassageBookmarkController {
    private(set) var passageID: String?
    private(set) var bookmark: Bookmark?
    private(set) var collections: [BookmarkCollection] = []
    /// Set when removing the bookmark would also delete a note; the view asks for confirmation.
    private(set) var isConfirmingRemoval = false
    /// A failed write, shown as an alert.
    var actionError: String?

    private let userData: UserDataContext

    init(userData: UserDataContext) {
        self.userData = userData
    }

    var isBookmarked: Bool { bookmark != nil }
    var note: String? { bookmark?.note }
    /// Bumps whenever bookmarks change anywhere in the app.
    var revision: Int { userData.changes.bookmarks }

    var collectionName: String? {
        guard let id = bookmark?.collectionID else { return nil }
        return collections.first { $0.id == id }?.name
    }

    /// Switches to a passage and reads its bookmark.
    func show(passageID: String) async {
        if self.passageID != passageID {
            self.passageID = passageID
            bookmark = nil
            isConfirmingRemoval = false
        }
        await refresh()
    }

    func refresh() async {
        guard let passageID else { return }
        let loaded = try? await userData.bookmarks.bookmark(passageID: passageID)
        let loadedCollections = (try? await userData.bookmarks.collections()) ?? []
        guard passageID == self.passageID else { return } // the user moved on meanwhile
        bookmark = loaded
        collections = loadedCollections
    }

    func toggle() async {
        guard let passageID else { return }
        if let bookmark {
            if bookmark.note != nil {
                isConfirmingRemoval = true
            } else {
                await remove()
            }
        } else {
            await perform { [userData] () async throws(AppError) in
                try await userData.bookmarks.addBookmark(passageID: passageID, at: userData.now())
            }
        }
    }

    func confirmRemoval() async {
        isConfirmingRemoval = false
        await remove()
    }

    func cancelRemoval() {
        isConfirmingRemoval = false
    }

    /// Saving a note bookmarks the passage; an empty note clears the note and keeps the bookmark.
    func saveNote(_ text: String) async {
        guard let passageID else { return }
        await perform { [userData] () async throws(AppError) in
            try await userData.bookmarks.setNote(text, passageID: passageID, at: userData.now())
        }
    }

    func move(toCollection id: UUID?) async {
        guard let passageID else { return }
        await perform { [userData] () async throws(AppError) in
            try await userData.bookmarks.moveBookmark(passageID: passageID, toCollection: id)
        }
    }

    func createCollectionAndMove(named name: String) async {
        guard let passageID, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await perform { [userData] () async throws(AppError) in
            let collection = try await userData.bookmarks.createCollection(named: name, at: userData.now())
            try await userData.bookmarks.addBookmark(passageID: passageID, at: userData.now())
            try await userData.bookmarks.moveBookmark(passageID: passageID, toCollection: collection.id)
        }
    }

    private func remove() async {
        guard let passageID else { return }
        await perform { [userData] () async throws(AppError) in
            try await userData.bookmarks.removeBookmark(passageID: passageID)
        }
    }

    private func perform(_ write: @MainActor () async throws(AppError) -> Void) async {
        do {
            try await write()
        } catch {
            actionError = error.userMessage
        }
        await refresh()
        userData.changes.bookmarksChanged()
    }
}
