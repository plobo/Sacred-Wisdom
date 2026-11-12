import Foundation
import SwiftData
import Testing
@testable import SacredWisdom

@Suite struct BookmarkRepositoryTests {
    private func makeRepository() throws -> SwiftDataBookmarkRepository {
        SwiftDataBookmarkRepository(modelContainer: try PersistenceManager.makeContainer(location: .inMemory))
    }

    private let t0 = Date(timeIntervalSince1970: 100)
    private let t1 = Date(timeIntervalSince1970: 200)

    @Test func addIsIdempotentAndListsNewestFirst() async throws {
        let repo = try makeRepository()
        let first = try await repo.addBookmark(passageID: "a", at: t0)
        let again = try await repo.addBookmark(passageID: "a", at: t1)
        try await repo.addBookmark(passageID: "b", at: t1)
        #expect(again.id == first.id)
        #expect(again.createdAt == t0)
        #expect(try await repo.bookmarks().map(\.passageID) == ["b", "a"])
        #expect(try await repo.bookmarkedPassageIDs() == ["a", "b"])
    }

    @Test func removeDeletesBookmarkAndNote() async throws {
        let repo = try makeRepository()
        try await repo.setNote("Reflection", passageID: "a", at: t0)
        try await repo.removeBookmark(passageID: "a")
        try await repo.removeBookmark(passageID: "missing") // no-op
        #expect(try await repo.bookmark(passageID: "a") == nil)
        #expect(try await repo.bookmarks().isEmpty)
    }

    @Test func noteBookmarksPassageAndEmptyNoteClearsOnlyTheNote() async throws {
        let repo = try makeRepository()
        let saved = try await repo.setNote("  On mercy.\n ", passageID: "a", at: t0)
        #expect(saved.note == "On mercy.")
        #expect(saved.noteUpdatedAt == t0)
        #expect(try await repo.bookmarkedPassageIDs() == ["a"])

        let cleared = try await repo.setNote("   ", passageID: "a", at: t1)
        #expect(cleared.note == nil)
        #expect(cleared.noteUpdatedAt == nil)
        #expect(try await repo.bookmark(passageID: "a") != nil)
    }

    @Test func noteIsCappedInLength() async throws {
        let repo = try makeRepository()
        let long = String(repeating: "x", count: SwiftDataBookmarkRepository.maximumNoteLength + 50)
        #expect(try await repo.setNote(long, passageID: "a", at: t0).note?.count == SwiftDataBookmarkRepository.maximumNoteLength)
    }

    @Test func collectionsCreateDedupeRenameAndMove() async throws {
        let repo = try makeRepository()
        let peace = try await repo.createCollection(named: "  Peace   studies ", at: t0)
        #expect(peace.name == "Peace studies")
        #expect(try await repo.createCollection(named: "peace STUDIES", at: t1).id == peace.id)
        let mercy = try await repo.createCollection(named: "Mercy", at: t1)
        #expect(try await repo.collections().map(\.name) == ["Peace studies", "Mercy"])

        try await repo.addBookmark(passageID: "a", at: t0)
        try await repo.moveBookmark(passageID: "a", toCollection: mercy.id)
        #expect(try await repo.bookmark(passageID: "a")?.collectionID == mercy.id)

        try await repo.renameCollection(id: mercy.id, to: "Compassion")
        #expect(try await repo.collections().map(\.name) == ["Peace studies", "Compassion"])
    }

    @Test func invalidCollectionOperationsThrow() async throws {
        let repo = try makeRepository()
        await #expect(throws: AppError.self) { try await repo.createCollection(named: "   ", at: t0) }
        try await repo.addBookmark(passageID: "a", at: t0)
        await #expect(throws: AppError.self) { try await repo.moveBookmark(passageID: "a", toCollection: UUID()) }
        await #expect(throws: AppError.self) { try await repo.moveBookmark(passageID: "unsaved", toCollection: nil) }
        await #expect(throws: AppError.self) { try await repo.renameCollection(id: UUID(), to: "x") }
    }

    @Test func deletingCollectionKeepsItsBookmarksUnfiled() async throws {
        let repo = try makeRepository()
        let group = try await repo.createCollection(named: "Group", at: t0)
        try await repo.addBookmark(passageID: "a", at: t0)
        try await repo.addBookmark(passageID: "b", at: t1)
        try await repo.moveBookmark(passageID: "a", toCollection: group.id)
        try await repo.deleteCollection(id: group.id)
        #expect(try await repo.collections().isEmpty)
        #expect(try await repo.bookmarks().map(\.collectionID) == [nil, nil])
    }
}

@Suite struct ReadingHistoryRepositoryTests {
    private func makeRepository() throws -> SwiftDataReadingHistoryRepository {
        SwiftDataReadingHistoryRepository(modelContainer: try PersistenceManager.makeContainer(location: .inMemory))
    }

    @Test func revisitMovesPassageToTopWithoutDuplicates() async throws {
        let repo = try makeRepository()
        try await repo.record(passageID: "a", at: Date(timeIntervalSince1970: 1))
        try await repo.record(passageID: "b", at: Date(timeIntervalSince1970: 2))
        try await repo.record(passageID: "a", at: Date(timeIntervalSince1970: 3))
        #expect(try await repo.recent(limit: 10).map(\.passageID) == ["a", "b"])
        #expect(try await repo.recent(limit: 1).map(\.passageID) == ["a"])
        #expect(try await repo.recent(limit: 0).isEmpty)
    }

    @Test func keepsOnlyTheNewestEntries() async throws {
        let repo = try makeRepository()
        let total = SwiftDataReadingHistoryRepository.maximumEntries + 5
        for index in 0..<total {
            try await repo.record(passageID: "p\(index)", at: Date(timeIntervalSince1970: Double(index)))
        }
        let all = try await repo.recent(limit: 1_000)
        #expect(all.count == SwiftDataReadingHistoryRepository.maximumEntries)
        #expect(all.first?.passageID == "p\(total - 1)")
    }

    @Test func clearRemovesEverything() async throws {
        let repo = try makeRepository()
        try await repo.record(passageID: "a", at: Date())
        try await repo.clear()
        #expect(try await repo.recent(limit: 10).isEmpty)
    }
}

/// Acceptance: "Bookmarks persist after app restart" and "User notes persist". A restart is a new container
/// over the same file, with new repository actors.
@Suite struct UserDataPersistenceTests {
    @Test func bookmarksNotesCollectionsAndHistorySurviveReopeningTheStore() async throws {
        let url = Fixtures.temporaryStoreURL()
        defer { PersistenceManager.deleteStore(at: url) }

        do {
            let container = try PersistenceManager.makeContainer(location: .file(url))
            let bookmarks = SwiftDataBookmarkRepository(modelContainer: container)
            let history = SwiftDataReadingHistoryRepository(modelContainer: container)
            let group = try await bookmarks.createCollection(named: "Mercy", at: Date(timeIntervalSince1970: 1))
            try await bookmarks.setNote("Compare with Al-Fatihah 1:1", passageID: "bible.matthew.5.7", at: Date(timeIntervalSince1970: 2))
            try await bookmarks.moveBookmark(passageID: "bible.matthew.5.7", toCollection: group.id)
            try await bookmarks.addBookmark(passageID: "quran.1.1", at: Date(timeIntervalSince1970: 3))
            try await history.record(passageID: "tanakh.psalms.23.1", at: Date(timeIntervalSince1970: 4))
        }

        let reopened = try PersistenceManager.makeContainer(location: .file(url))
        let bookmarks = SwiftDataBookmarkRepository(modelContainer: reopened)
        let history = SwiftDataReadingHistoryRepository(modelContainer: reopened)
        #expect(try await bookmarks.bookmarks().map(\.passageID) == ["quran.1.1", "bible.matthew.5.7"])
        let noted = try #require(try await bookmarks.bookmark(passageID: "bible.matthew.5.7"))
        #expect(noted.note == "Compare with Al-Fatihah 1:1")
        #expect(try await bookmarks.collections().map(\.name) == ["Mercy"])
        #expect(noted.collectionID == (try await bookmarks.collections()).first?.id)
        #expect(try await history.recent(limit: 5).map(\.passageID) == ["tanakh.psalms.23.1"])
    }

    @Test func deleteStoreRemovesFileAndSidecars() async throws {
        let url = Fixtures.temporaryStoreURL()
        do {
            let container = try PersistenceManager.makeContainer(location: .file(url))
            try await SwiftDataBookmarkRepository(modelContainer: container).addBookmark(passageID: "a", at: Date())
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        PersistenceManager.deleteStore(at: url)
        for suffix in ["", "-shm", "-wal"] {
            #expect(!FileManager.default.fileExists(atPath: url.path + suffix))
        }
        let fresh = SwiftDataBookmarkRepository(modelContainer: try PersistenceManager.makeContainer(location: .file(url)))
        #expect(try await fresh.bookmarks().isEmpty)
        PersistenceManager.deleteStore(at: url)
    }
}

@Suite struct AppConfigurationTests {
    @Test func productionAlwaysUsesTheDefaultStore() {
        let location = AppConfiguration.userDataLocation(
            arguments: ["app", AppConfiguration.userDataStoreArgument, "x"], isUITesting: false)
        #expect(location == .defaultFile)
    }

    @Test func uiTestsUseMemoryUnlessAStoreIsNamed() {
        #expect(AppConfiguration.userDataLocation(arguments: ["app", "-ui-testing"], isUITesting: true) == .inMemory)
        #expect(AppConfiguration.userDataLocation(
            arguments: ["app", AppConfiguration.userDataStoreArgument], isUITesting: true) == .inMemory)
        let named = AppConfiguration.userDataLocation(
            arguments: ["app", AppConfiguration.userDataStoreArgument, "../persist-1"], isUITesting: true)
        let expected = FileManager.default.temporaryDirectory.appendingPathComponent("persist-1.store")
        #expect(named == .file(expected)) // path characters are stripped: the store stays in the temp directory
    }
}
