import Foundation

protocol SearchScriptureUseCaseProtocol: Sendable {
    func execute(_ text: String, filters: SearchFilters) async throws(AppError) -> SearchResults
}

/// Parses the query, searches every installed tradition, and groups results by tradition.
/// Groups follow the fixed tradition order (not relevance), so no tradition is ranked above another.
struct SearchScriptureUseCase: SearchScriptureUseCaseProtocol {
    let search: any ScriptureSearchRepository
    let religions: any ReligionRepository

    func execute(_ text: String, filters: SearchFilters) async throws(AppError) -> SearchResults {
        let query = SearchQueryParser.parse(text)
        guard !query.isEmpty else { return SearchResults(query: query, groups: []) }

        let results = try await search.search(query: query, filters: filters)
        let traditions = try await religions.fetchReligions().sorted { $0.sortOrder < $1.sortOrder }
        let collectionNames = Dictionary(
            try await religions.fetchCollections().map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        let byReligion = Dictionary(grouping: results, by: \.passage.religionID)
        let groups = traditions.compactMap { religion -> SearchResultGroup? in
            guard let matches = byReligion[religion.id], !matches.isEmpty else { return nil }
            let ordered = matches.sorted { lhs, rhs in
                if lhs.matchedAllTerms != rhs.matchedAllTerms { return lhs.matchedAllTerms }
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.passage.id < rhs.passage.id
            }
            return SearchResultGroup(religion: religion, collectionNames: collectionNames, results: ordered)
        }
        return SearchResults(query: query, groups: groups)
    }
}
