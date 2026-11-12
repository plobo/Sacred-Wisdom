import Foundation

/// One FTS5 match: a passage in one translation, with its weighted bm25 rank (lower is better).
struct FullTextHit: Sendable, Equatable {
    let passageID: String
    let translationID: String
    let collectionID: String
    let religionID: String
    let rank: Double
}

/// Query access to the `passage_search` FTS5 table.
/// User text is never spliced into MATCH syntax: every word is quoted, so FTS operators are inert.
struct FullTextSearchIndex: Sendable {
    enum Combinator: Sendable {
        /// Every clause must match.
        case all
        /// Any clause may match.
        case any
    }

    /// bm25 column weights, in table column order (the five UNINDEXED columns first).
    /// A match in the reference counts most; titles count least.
    static let columnWeights = "0, 0, 0, 0, 0, 1.0, 1.0, 0.4, 0.4, 3.0"

    let database: DatabaseManager

    func search(
        _ query: SearchQuery,
        combinator: Combinator = .all,
        filters: SearchFilters = SearchFilters(),
        limit: Int = 100
    ) async throws(AppError) -> [FullTextHit] {
        guard let match = Self.matchExpression(query.clauses, combinator: combinator), limit > 0 else { return [] }
        var sql = """
            SELECT passage_id, translation_id, collection_id, religion_id,
                   bm25(passage_search, \(Self.columnWeights)) AS rank
            FROM passage_search
            WHERE passage_search MATCH ?
            """
        var bindings: [SQLiteValue] = [.text(match)]
        func restrict(_ column: String, _ values: Set<String>) {
            guard !values.isEmpty else { return }
            let sorted = values.sorted()
            sql += " AND \(column) IN (\(Self.placeholders(sorted.count)))"
            bindings += sorted.map { .text($0) }
        }
        restrict("religion_id", filters.religionIDs)
        restrict("collection_id", filters.collectionIDs)
        restrict("translation_id", filters.translationIDs)
        if !filters.languageCodes.isEmpty {
            let codes = filters.languageCodes.sorted()
            sql += """
                 AND (language_code IN (\(Self.placeholders(codes.count)))
                      OR collection_id IN (SELECT id FROM scripture_collections
                                           WHERE original_language IN (\(Self.placeholders(codes.count)))))
                """
            bindings += codes.map { .text($0) } + codes.map { .text($0) }
        }
        sql += " ORDER BY rank, passage_id LIMIT ?;"
        bindings.append(.integer(limit))

        let db = try await database.connection()
        var hits: [FullTextHit] = []
        for row in try await db.query(sql, bindings) {
            hits.append(FullTextHit(
                passageID: try row.string("passage_id"),
                translationID: try row.string("translation_id"),
                collectionID: try row.string("collection_id"),
                religionID: try row.string("religion_id"),
                rank: try row.double("rank")
            ))
        }
        return hits
    }

    /// Convenience used by tests and simple callers: plain words, all or as a phrase.
    func search(terms: [String], phrase: Bool = false, religionIDs: Set<String> = [], limit: Int = 100) async throws(AppError) -> [FullTextHit] {
        let words = terms.flatMap { SearchTextNormalizer.words(in: SearchTextNormalizer.normalize($0)) }
        let clauses: [SearchQuery.Clause] = phrase ? [.phrase(words)] : words.map { .term($0, prefix: false) }
        return try await search(SearchQuery(clauses: words.isEmpty ? [] : clauses, droppedStopWords: []),
                                filters: SearchFilters(religionIDs: religionIDs), limit: limit)
    }

    /// Builds a safe MATCH expression, or nil when there is nothing to search for.
    static func matchExpression(_ clauses: [SearchQuery.Clause], combinator: Combinator) -> String? {
        let parts = clauses.compactMap { clause -> String? in
            switch clause {
            case .term(let word, let prefix):
                let quoted = quote(word)
                guard !quoted.isEmpty else { return nil }
                return prefix ? quoted + " *" : quoted
            case .phrase(let words):
                let quoted = words.map(quote).filter { !$0.isEmpty }
                return quoted.isEmpty ? nil : quoted.joined(separator: " + ")
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: combinator == .all ? " " : " OR ")
    }

    private static func quote(_ word: String) -> String {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : "\"" + trimmed.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}
