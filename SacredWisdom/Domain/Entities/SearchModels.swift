import Foundation

/// Restricts a search. Empty sets mean "no restriction".
struct SearchFilters: Hashable, Sendable {
    var religionIDs: Set<String> = []
    var collectionIDs: Set<String> = []
    /// Matches a collection's original language or a translation's language.
    var languageCodes: Set<String> = []
    var translationIDs: Set<String> = []

    var isEmpty: Bool {
        religionIDs.isEmpty && collectionIDs.isEmpty && languageCodes.isEmpty && translationIDs.isEmpty
    }

    var activeCount: Int {
        [religionIDs, collectionIDs, languageCodes, translationIDs].filter { !$0.isEmpty }.count
    }
}

/// A parsed, normalized query.
struct SearchQuery: Hashable, Sendable {
    enum Clause: Hashable, Sendable {
        /// A single word; `prefix` also matches words that start with it.
        case term(String, prefix: Bool)
        /// Words that must appear consecutively.
        case phrase([String])
    }

    enum Mode: Sendable {
        case keyword, phrase, mixed
    }

    let clauses: [Clause]
    /// Keywords removed as stop words; used only by the any-word fallback.
    let droppedStopWords: [String]

    var isEmpty: Bool { clauses.isEmpty }

    var mode: Mode {
        let phrases = clauses.filter { if case .phrase = $0 { true } else { false } }.count
        if phrases == 0 { return .keyword }
        return phrases == clauses.count ? .phrase : .mixed
    }

    var keywordTerms: [String] {
        clauses.compactMap { if case .term(let t, _) = $0 { t } else { nil } }
    }

    /// Every word in the query, for highlighting.
    var highlightTerms: [String] {
        clauses.flatMap { clause -> [String] in
            switch clause {
            case .term(let t, _): [t]
            case .phrase(let words): words
            }
        }
    }
}

/// One passage that matched a search.
struct ScriptureSearchResult: Identifiable, Hashable, Sendable {
    let passage: ScripturePassage
    /// The translation whose text matched best (or the default when only the original matched).
    let matchedTranslationID: String
    /// Higher is more relevant.
    let score: Double
    /// True when every query clause matched; false for any-word fallback matches.
    let matchedAllTerms: Bool

    var id: String { passage.id }

    var previewText: PassageText? { passage.text(preferring: matchedTranslationID) }
}

/// Results for one tradition, for grouped display.
struct SearchResultGroup: Identifiable, Equatable, Sendable {
    let religion: Religion
    let collectionNames: [String: String]
    let results: [ScriptureSearchResult]

    var id: String { religion.id }
}

struct SearchResults: Equatable, Sendable {
    let query: SearchQuery
    let groups: [SearchResultGroup]

    var totalCount: Int { groups.reduce(0) { $0 + $1.results.count } }
    var isEmpty: Bool { groups.isEmpty }
}

struct SearchHistoryItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let query: String
    let searchedAt: Date
}

/// Options offered in the filter UI, derived from installed content.
struct SearchFilterOptions: Equatable, Sendable {
    let religions: [Religion]
    let collections: [ScriptureCollection]
    let languageCodes: [String]
    let translations: [Translation]
}
