import Foundation
import SwiftData

@ModelActor
actor SwiftDataBookmarkRepository: BookmarkRepository {
    static let maximumNoteLength = 10_000
    static let maximumCollectionNameLength = 60

    // MARK: Bookmarks

    func bookmarks() throws(AppError) -> [Bookmark] {
        try fetch(FetchDescriptor<UserBookmark>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])).map(Self.domain)
    }

    func bookmark(passageID: String) throws(AppError) -> Bookmark? {
        try entry(passageID: passageID).map(Self.domain)
    }

    func bookmarkedPassageIDs() throws(AppError) -> Set<String> {
        Set(try fetch(FetchDescriptor<UserBookmark>()).map(\.passageID))
    }

    @discardableResult
    func addBookmark(passageID: String, at date: Date) throws(AppError) -> Bookmark {
        if let existing = try entry(passageID: passageID) { return Self.domain(existing) }
        let entry = UserBookmark(passageID: passageID, createdAt: date)
        modelContext.insert(entry)
        try save()
        return Self.domain(entry)
    }

    func removeBookmark(passageID: String) throws(AppError) {
        guard let entry = try entry(passageID: passageID) else { return }
        modelContext.delete(entry)
        try save()
    }

    @discardableResult
    func setNote(_ note: String, passageID: String, at date: Date) throws(AppError) -> Bookmark {
        let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumNoteLength))
        let entry: UserBookmark
        if let existing = try self.entry(passageID: passageID) {
            entry = existing
        } else {
            entry = UserBookmark(passageID: passageID, createdAt: date)
            modelContext.insert(entry)
        }
        entry.note = trimmed.isEmpty ? nil : trimmed
        entry.noteUpdatedAt = trimmed.isEmpty ? nil : date
        try save()
        return Self.domain(entry)
    }

    func moveBookmark(passageID: String, toCollection collectionID: UUID?) throws(AppError) {
        guard let entry = try entry(passageID: passageID) else { throw .contentNotFound("bookmark \(passageID)") }
        if let collectionID {
            guard try collectionEntry(id: collectionID) != nil else { throw .contentNotFound("collection \(collectionID)") }
        }
        entry.customCollectionID = collectionID
        try save()
    }

    // MARK: Collections

    func collections() throws(AppError) -> [BookmarkCollection] {
        try fetchCollections(FetchDescriptor<UserCollection>(sortBy: [SortDescriptor(\.createdAt)])).map(Self.domain)
    }

    @discardableResult
    func createCollection(named name: String, at date: Date) throws(AppError) -> BookmarkCollection {
        let cleaned = try Self.cleanName(name)
        let key = Self.comparisonKey(cleaned)
        if let existing = try fetchCollections(FetchDescriptor<UserCollection>()).first(where: { Self.comparisonKey($0.name) == key }) {
            return Self.domain(existing)
        }
        let entry = UserCollection(name: cleaned, createdAt: date)
        modelContext.insert(entry)
        try save()
        return Self.domain(entry)
    }

    func renameCollection(id: UUID, to name: String) throws(AppError) {
        let cleaned = try Self.cleanName(name)
        guard let entry = try collectionEntry(id: id) else { throw .contentNotFound("collection \(id)") }
        entry.name = cleaned
        try save()
    }

    func deleteCollection(id: UUID) throws(AppError) {
        guard let entry = try collectionEntry(id: id) else { return }
        let target: UUID? = id
        for bookmark in try fetch(FetchDescriptor<UserBookmark>(predicate: #Predicate { $0.customCollectionID == target })) {
            bookmark.customCollectionID = nil
        }
        modelContext.delete(entry)
        try save()
    }

    // MARK: Private

    private func entry(passageID: String) throws(AppError) -> UserBookmark? {
        try fetch(FetchDescriptor<UserBookmark>(predicate: #Predicate { $0.passageID == passageID })).first
    }

    private func collectionEntry(id: UUID) throws(AppError) -> UserCollection? {
        try fetchCollections(FetchDescriptor<UserCollection>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetch(_ descriptor: FetchDescriptor<UserBookmark>) throws(AppError) -> [UserBookmark] {
        do { return try modelContext.fetch(descriptor) } catch { throw .userData("Bookmarks: \(error)") }
    }

    private func fetchCollections(_ descriptor: FetchDescriptor<UserCollection>) throws(AppError) -> [UserCollection] {
        do { return try modelContext.fetch(descriptor) } catch { throw .userData("Collections: \(error)") }
    }

    private func save() throws(AppError) {
        do { try modelContext.save() } catch { throw .userData("Bookmarks: \(error)") }
    }

    private static func cleanName(_ name: String) throws(AppError) -> String {
        let cleaned = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !cleaned.isEmpty else { throw .userData("empty collection name") }
        return String(cleaned.prefix(maximumCollectionNameLength))
    }

    private static func comparisonKey(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private static func domain(_ entry: UserBookmark) -> Bookmark {
        Bookmark(id: entry.id, passageID: entry.passageID, createdAt: entry.createdAt, note: entry.note,
                 noteUpdatedAt: entry.noteUpdatedAt, collectionID: entry.customCollectionID)
    }

    private static func domain(_ entry: UserCollection) -> BookmarkCollection {
        BookmarkCollection(id: entry.id, name: entry.name, createdAt: entry.createdAt)
    }
}

@ModelActor
actor SwiftDataReadingHistoryRepository: ReadingHistoryRepository {
    static let maximumEntries = 100

    func record(passageID: String, at date: Date) throws(AppError) {
        if let existing = try fetch(FetchDescriptor<ReadingHistoryEntry>(predicate: #Predicate { $0.passageID == passageID })).first {
            existing.viewedAt = date
        } else {
            modelContext.insert(ReadingHistoryEntry(passageID: passageID, viewedAt: date))
        }
        let all = try fetch(FetchDescriptor<ReadingHistoryEntry>(sortBy: [SortDescriptor(\.viewedAt, order: .reverse)]))
        for stale in all.dropFirst(Self.maximumEntries) { modelContext.delete(stale) }
        try save()
    }

    func recent(limit: Int) throws(AppError) -> [ReadingHistoryItem] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<ReadingHistoryEntry>(sortBy: [SortDescriptor(\.viewedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try fetch(descriptor).map { ReadingHistoryItem(passageID: $0.passageID, viewedAt: $0.viewedAt) }
    }

    func clear() throws(AppError) {
        for entry in try fetch(FetchDescriptor<ReadingHistoryEntry>()) { modelContext.delete(entry) }
        try save()
    }

    private func fetch(_ descriptor: FetchDescriptor<ReadingHistoryEntry>) throws(AppError) -> [ReadingHistoryEntry] {
        do { return try modelContext.fetch(descriptor) } catch { throw .userData("Reading history: \(error)") }
    }

    private func save() throws(AppError) {
        do { try modelContext.save() } catch { throw .userData("Reading history: \(error)") }
    }
}

/// Used when the user data store cannot be opened. Reads are empty; writes report the failure.
struct UnavailableUserDataRepository: BookmarkRepository, ReadingHistoryRepository {
    private var failure: AppError { .userData("store unavailable") }

    func bookmarks() async throws(AppError) -> [Bookmark] { [] }
    func bookmark(passageID: String) async throws(AppError) -> Bookmark? { nil }
    func bookmarkedPassageIDs() async throws(AppError) -> Set<String> { [] }
    func addBookmark(passageID: String, at date: Date) async throws(AppError) -> Bookmark { throw failure }
    func removeBookmark(passageID: String) async throws(AppError) { throw failure }
    func setNote(_ note: String, passageID: String, at date: Date) async throws(AppError) -> Bookmark { throw failure }
    func moveBookmark(passageID: String, toCollection collectionID: UUID?) async throws(AppError) { throw failure }
    func collections() async throws(AppError) -> [BookmarkCollection] { [] }
    func createCollection(named name: String, at date: Date) async throws(AppError) -> BookmarkCollection { throw failure }
    func renameCollection(id: UUID, to name: String) async throws(AppError) { throw failure }
    func deleteCollection(id: UUID) async throws(AppError) { throw failure }

    func record(passageID: String, at date: Date) async throws(AppError) {}
    func recent(limit: Int) async throws(AppError) -> [ReadingHistoryItem] { [] }
    func clear() async throws(AppError) {}
}
