import Foundation

/// Merges the keyword repository with optional supplementary ones (e.g. semantic search, Phase 7+).
/// The keyword search is authoritative: a supplementary failure is ignored, never surfaced,
/// so local keyword search always works.
struct CombinedSearchRepository: ScriptureSearchRepository {
    let primary: any ScriptureSearchRepository
    let supplementary: [any ScriptureSearchRepository]

    func search(query: SearchQuery, filters: SearchFilters) async throws(AppError) -> [ScriptureSearchResult] {
        var results = try await primary.search(query: query, filters: filters)
        var seen = Set(results.map(\.id))
        for repository in supplementary {
            guard let extra = try? await repository.search(query: query, filters: filters) else { continue }
            for result in extra where seen.insert(result.id).inserted {
                results.append(result)
            }
        }
        return results
    }
}
