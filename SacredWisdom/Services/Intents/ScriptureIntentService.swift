import Foundation

/// What Siri / Shortcuts get back: spoken text plus the passages it refers to.
/// Every quotation is verbatim from the database and names its reference.
struct IntentResponse: Equatable, Sendable {
    let dialog: String
    let passages: [ScripturePassage]
}

/// Topics offered as App Shortcut phrases ("Find verses about peace"). Each maps to a plain search query.
enum ScriptureTopicQuery: String, CaseIterable, Sendable {
    case peace, mercy, comfort, love, hatred, guidance, action, truth, fear, righteousness, forgiveness

    /// The words the passages themselves use: "path" for guidance; "true" also matches "truth" as a prefix.
    var query: String {
        switch self {
        case .guidance: "path"
        case .truth: "true"
        default: rawValue
        }
    }

    var displayName: String { rawValue.capitalized }
}

/// The logic behind every App Intent, kept free of the AppIntents framework so it can be unit tested.
/// Answers are built only from retrieved passages; nothing is generated (AI arrives in Phase 7).
struct ScriptureIntentService: Sendable {
    /// Spoken answers stay short: at most this many passages are named or quoted.
    static let spokenLimit = 3

    let search: any SearchScriptureUseCaseProtocol
    let scripture: any ScriptureRepository & ReligionRepository & PassageRepository

    /// SearchScriptureIntent: names the best references, one per tradition.
    func searchReferences(_ query: String) async throws(AppError) -> IntentResponse {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return IntentResponse(dialog: String(localized: "What would you like to search for?"), passages: []) }
        let results = try await search.execute(cleaned, filters: SearchFilters())
        guard !results.isEmpty else { return notFound(cleaned) }
        let best = Self.bestPerTradition(results)
        let named = best.prefix(Self.spokenLimit).map { "\($0.reference) (\($0.religion))" }
        let summary = SearchResultsSummary.text(passages: results.totalCount, traditions: results.groups.count)
        let dialog = String(localized: "Found \(summary) for “\(cleaned)”. Top matches: \(Self.list(named)).")
        return IntentResponse(dialog: dialog, passages: results.groups.flatMap { $0.results.map(\.passage) })
    }

    /// AskQuestionIntent: a concise response quoting the best passage from up to three traditions.
    func answer(_ question: String) async throws(AppError) -> IntentResponse {
        let cleaned = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return IntentResponse(dialog: String(localized: "What would you like to ask?"), passages: []) }
        let results = try await search.execute(cleaned, filters: SearchFilters())
        guard !results.isEmpty else { return notFound(cleaned) }
        let best = Self.bestPerTradition(results)
        let quotes = best.prefix(Self.spokenLimit).map { item in
            "\(item.religion), \(item.reference): \(item.text)"
        }
        let intro = best.count == 1
            ? String(localized: "One passage speaks to this.")
            : String(localized: "Passages from \(best.count) traditions speak to this.")
        var dialog = intro + " " + quotes.joined(separator: " ")
        if best.count > Self.spokenLimit {
            dialog += " " + String(localized: "Open Sacred Wisdom to see all of them.")
        }
        return IntentResponse(dialog: dialog, passages: best.map(\.passage))
    }

    /// DailyVerseIntent.
    func dailyPassage(on date: Date) async throws(AppError) -> IntentResponse {
        guard let passage = try await scripture.dailyPassage(on: date) else {
            return IntentResponse(dialog: String(localized: "No passages are installed yet."), passages: [])
        }
        let collection = try await scripture.collection(id: passage.collectionID)
        let text = passage.texts.first
        let quote = text.map { " \($0.text) (\($0.translation.name))" } ?? ""
        let dialog = String(localized: "Today’s passage is \(passage.reference) from the \(collection.name).") + quote
        return IntentResponse(dialog: dialog, passages: [passage])
    }

    // MARK: Helpers

    private struct Pick {
        let passage: ScripturePassage
        let religion: String
        let reference: String
        let text: String
    }

    /// The top result of each tradition, in relevance order (full matches before partial ones).
    private static func bestPerTradition(_ results: SearchResults) -> [Pick] {
        results.groups
            .compactMap { group -> (ScriptureSearchResult, Religion)? in group.results.first.map { ($0, group.religion) } }
            .sorted { lhs, rhs in
                if lhs.0.matchedAllTerms != rhs.0.matchedAllTerms { return lhs.0.matchedAllTerms }
                return lhs.0.score > rhs.0.score
            }
            .map { result, religion in
                Pick(passage: result.passage, religion: religion.name, reference: result.passage.reference,
                     text: result.previewText?.text ?? "")
            }
    }

    private func notFound(_ query: String) -> IntentResponse {
        IntentResponse(
            dialog: String(localized: "I couldn’t find passages about “\(query)” in the installed library."),
            passages: []
        )
    }

    private static func list(_ items: [String]) -> String {
        ListFormatter.localizedString(byJoining: items)
    }
}
