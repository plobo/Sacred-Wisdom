import Foundation

protocol ScriptureSearchRepository: Sendable {
    func search(query: SearchQuery, filters: SearchFilters) async throws(AppError) -> [ScriptureSearchResult]
}

protocol SearchHistoryRepository: Sendable {
    /// Newest first.
    func recent(limit: Int) async throws(AppError) -> [SearchHistoryItem]
    /// Records a query; an existing entry with the same normalized text moves to the top.
    func record(_ query: String, at date: Date) async throws(AppError)
    func remove(id: UUID) async throws(AppError)
    func clear() async throws(AppError)
}
