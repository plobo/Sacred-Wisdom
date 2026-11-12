import Foundation

/// Suggested questions and type-ahead completions. Questions are phrased neutrally and are
/// answered only by retrieving verified passages; nothing here is scripture.
struct SearchSuggestionProvider: Sendable {
    /// Each question must return results from the installed content (enforced by an integration test).
    static let suggestedQuestions: [String] = [
        "What is said about peace?",
        "What is said about the merciful?",
        "How can hatred cease?",
        "What is said about action and its fruits?",
        "Where is comfort found?",
        "What is said about God's order?",
    ]

    /// Completions for partially typed text: matching recent searches first, then suggested questions.
    func completions(for text: String, recent: [SearchHistoryItem], limit: Int = 5) -> [String] {
        let typed = SearchTextNormalizer.normalize(text).trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }
        var results: [String] = []
        for candidate in recent.map(\.query) + Self.suggestedQuestions {
            let folded = SearchTextNormalizer.normalize(candidate)
            guard folded != typed, folded.contains(typed),
                  !results.contains(where: { SearchTextNormalizer.normalize($0) == folded }) else { continue }
            results.append(candidate)
            if results.count == limit { break }
        }
        return results
    }
}
