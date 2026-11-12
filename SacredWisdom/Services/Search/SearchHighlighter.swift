import Foundation

/// Finds where query words occur in verbatim display text, ignoring case and diacritics.
/// Only attributes are added for display; the text itself is never altered.
enum SearchHighlighter {
    static func ranges(of terms: [String], in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for term in Set(terms) where !term.isEmpty {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive],
                                         range: searchStart..<text.endIndex) {
                if isWordStart(range.lowerBound, in: text) {
                    found.append(range.lowerBound..<wordEnd(from: range.upperBound, in: text))
                }
                searchStart = range.upperBound
            }
        }
        return merge(found)
    }

    /// True when any term occurs in the text after both are folded (handles unpointed Arabic/Hebrew queries).
    static func matchesFolded(_ terms: [String], in text: String) -> Bool {
        let words = SearchTextNormalizer.words(in: SearchTextNormalizer.normalize(text))
        return terms.contains { term in words.contains { $0.hasPrefix(term) } }
    }

    static func attributed(_ text: String, terms: [String]) -> AttributedString {
        var result = AttributedString(text)
        for range in ranges(of: terms, in: text) {
            guard let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return result
    }

    private static func isWordStart(_ index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        let previous = text[text.index(before: index)]
        return !(previous.isLetter || previous.isNumber)
    }

    /// Extends a prefix match to the end of the word ("forgiv" highlights "forgiveness").
    private static func wordEnd(from index: String.Index, in text: String) -> String.Index {
        var end = index
        while end < text.endIndex, text[end].isLetter || text[end].isNumber { end = text.index(after: end) }
        return end
    }

    private static func merge(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        var merged: [Range<String.Index>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
