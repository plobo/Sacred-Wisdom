import Foundation
import SwiftData

@ModelActor
actor SwiftDataSearchHistoryRepository: SearchHistoryRepository {
    static let maximumEntries = 20

    func recent(limit: Int) throws(AppError) -> [SearchHistoryItem] {
        var descriptor = FetchDescriptor<SearchHistoryEntry>(sortBy: [SortDescriptor(\.searchedAt, order: .reverse)])
        descriptor.fetchLimit = max(limit, 0)
        guard limit > 0 else { return [] }
        return try fetch(descriptor).map { SearchHistoryItem(id: $0.id, query: $0.query, searchedAt: $0.searchedAt) }
    }

    func record(_ query: String, at date: Date) throws(AppError) {
        let display = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = SearchTextNormalizer.words(in: SearchTextNormalizer.normalize(display)).joined(separator: " ")
        guard !normalized.isEmpty else { return }

        let existing = try fetch(FetchDescriptor<SearchHistoryEntry>(predicate: #Predicate { $0.normalizedQuery == normalized }))
        if let entry = existing.first {
            entry.query = display
            entry.searchedAt = date
        } else {
            modelContext.insert(SearchHistoryEntry(query: display, normalizedQuery: normalized, searchedAt: date))
        }
        let all = try fetch(FetchDescriptor<SearchHistoryEntry>(sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]))
        for stale in all.dropFirst(Self.maximumEntries) { modelContext.delete(stale) }
        try save()
    }

    func remove(id: UUID) throws(AppError) {
        for entry in try fetch(FetchDescriptor<SearchHistoryEntry>(predicate: #Predicate { $0.id == id })) {
            modelContext.delete(entry)
        }
        try save()
    }

    func clear() throws(AppError) {
        for entry in try fetch(FetchDescriptor<SearchHistoryEntry>()) { modelContext.delete(entry) }
        try save()
    }

    private func fetch(_ descriptor: FetchDescriptor<SearchHistoryEntry>) throws(AppError) -> [SearchHistoryEntry] {
        do { return try modelContext.fetch(descriptor) } catch { throw .database("Search history: \(error)") }
    }

    private func save() throws(AppError) {
        do { try modelContext.save() } catch { throw .database("Search history: \(error)") }
    }
}

/// Used when the user data store cannot be opened: search still works, history is simply empty.
struct UnavailableSearchHistoryRepository: SearchHistoryRepository {
    func recent(limit: Int) async throws(AppError) -> [SearchHistoryItem] { [] }
    func record(_ query: String, at date: Date) async throws(AppError) {}
    func remove(id: UUID) async throws(AppError) {}
    func clear() async throws(AppError) {}
}
