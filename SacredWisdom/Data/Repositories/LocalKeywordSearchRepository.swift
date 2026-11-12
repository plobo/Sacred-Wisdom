import Foundation

/// Keyword and phrase search over the local FTS5 index. Works fully offline.
///
/// Ranking: passages matching every clause come first (ordered by weighted bm25). If that leaves fewer than
/// `fallbackThreshold` results and the query has several keywords, passages matching any keyword are appended
/// after them, so natural-language questions still find something.
struct LocalKeywordSearchRepository: ScriptureSearchRepository {
    static let fallbackThreshold = 10
    static let resultLimit = 100

    let index: FullTextSearchIndex
    let scripture: any ScriptureRepository & ReligionRepository

    func search(query: SearchQuery, filters: SearchFilters) async throws(AppError) -> [ScriptureSearchResult] {
        guard !query.isEmpty else { return [] }
        let defaults = try await defaultTranslations()
        var best = Self.bestHitPerPassage(
            try await index.search(query, combinator: .all, filters: filters, limit: Self.resultLimit * 4),
            matchedAll: true, defaults: defaults
        )
        if best.count < Self.fallbackThreshold, query.clauses.count > 1 {
            let any = Self.bestHitPerPassage(
                try await index.search(query, combinator: .any, filters: filters, limit: Self.resultLimit * 4),
                matchedAll: false, defaults: defaults
            )
            for candidate in any where !best.contains(where: { $0.passageID == candidate.passageID }) {
                best.append(candidate)
            }
        }

        let candidates = Array(best.prefix(Self.resultLimit))
        let passages = Dictionary(
            try await scripture.passages(ids: candidates.map(\.passageID)).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return candidates.compactMap { candidate in
            passages[candidate.passageID].map { passage in
                ScriptureSearchResult(passage: passage, matchedTranslationID: candidate.translationID,
                                      score: -candidate.rank, matchedAllTerms: candidate.matchedAll)
            }
        }
    }

    private struct Candidate {
        let passageID: String
        let translationID: String
        let rank: Double
        let matchedAll: Bool
    }

    private func defaultTranslations() async throws(AppError) -> [String: String] {
        var defaults: [String: String] = [:]
        for collection in try await scripture.fetchCollections() {
            defaults[collection.id] = collection.defaultTranslationID
        }
        return defaults
    }

    /// Several translations of one passage can match. The passage ranks by its best hit; the translation shown
    /// is the collection's default when it matched, otherwise the best-ranked one (e.g. "gentle" → WEB only).
    /// Input is ordered by rank, so the first hit per passage is its best.
    private static func bestHitPerPassage(_ hits: [FullTextHit], matchedAll: Bool, defaults: [String: String]) -> [Candidate] {
        var order: [String] = []
        var byPassage: [String: [FullTextHit]] = [:]
        for hit in hits {
            if byPassage[hit.passageID] == nil { order.append(hit.passageID) }
            byPassage[hit.passageID, default: []].append(hit)
        }
        return order.compactMap { id in
            guard let passageHits = byPassage[id], let best = passageHits.first else { return nil }
            let preferred = passageHits.first { $0.translationID == defaults[best.collectionID] } ?? best
            return Candidate(passageID: id, translationID: preferred.translationID, rank: best.rank, matchedAll: matchedAll)
        }
    }
}
