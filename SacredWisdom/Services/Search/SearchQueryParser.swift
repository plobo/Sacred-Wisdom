import Foundation

/// Turns raw user input into a `SearchQuery`.
///
/// * Text inside double quotes (straight or curly) is an exact phrase.
/// * Remaining words are keywords. English stop words are dropped when other keywords remain,
///   so a question like "What is said about mercy?" searches for "mercy".
/// * Keywords of three or more characters also match as prefixes ("forgiv" finds "forgiveness").
enum SearchQueryParser {
    static let minimumPrefixLength = 3

    static let stopWords: Set<String> = [
        "a", "about", "an", "and", "are", "as", "at", "be", "by", "can", "did", "do", "does", "for", "from",
        "has", "have", "how", "i", "in", "is", "it", "its", "me", "my", "of", "on", "or", "our", "religion",
        "religions", "said", "say", "says", "should", "tell", "teach", "teaches", "that", "the", "their",
        "there", "they", "this", "to", "us", "was", "we", "what", "when", "where", "which", "who", "why",
        "will", "with", "you", "your",
    ]

    static func parse(_ input: String) -> SearchQuery {
        var clauses: [SearchQuery.Clause] = []
        var keywords: [String] = []
        for (index, segment) in split(input).enumerated() {
            let words = SearchTextNormalizer.words(in: SearchTextNormalizer.normalize(segment))
            guard !words.isEmpty else { continue }
            if index.isMultiple(of: 2) {
                keywords += words
            } else {
                clauses.append(words.count == 1 ? .term(words[0], prefix: false) : .phrase(words))
            }
        }

        var unique: [String] = []
        for word in keywords where !unique.contains(word) { unique.append(word) }
        let meaningful = unique.filter { !stopWords.contains($0) }
        let kept = (meaningful.isEmpty && clauses.isEmpty) ? unique : meaningful
        let dropped = unique.filter { !kept.contains($0) }

        let terms = kept.map { SearchQuery.Clause.term($0, prefix: $0.count >= minimumPrefixLength) }
        return SearchQuery(clauses: terms + clauses, droppedStopWords: dropped)
    }

    /// Alternates outside-quote / inside-quote segments: even indexes are free text, odd are phrases.
    /// An unbalanced quote treats the rest of the input as a phrase.
    private static func split(_ input: String) -> [String] {
        let normalizedQuotes = input.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        return normalizedQuotes.components(separatedBy: "\"")
    }
}
