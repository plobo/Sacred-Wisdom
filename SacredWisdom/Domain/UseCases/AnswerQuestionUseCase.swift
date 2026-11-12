import Foundation

protocol AnswerQuestionUseCaseProtocol: Sendable {
    func execute(_ question: String) async throws(AppError) -> QuestionAnswer
}

/// Retrieval first, AI second:
/// 1. local search finds verified passages (works without AI);
/// 2. if AI is enabled and available, the best passages, interleaved across traditions, become its context;
/// 3. the reply is validated against those passages before anything is shown.
/// A search failure throws; any AI problem only changes `explanation`, never the passages.
struct AnswerQuestionUseCase: AnswerQuestionUseCaseProtocol {
    let search: any SearchScriptureUseCaseProtocol
    let ai: any ScriptureAIService
    let preferences: any AIPreferenceStore
    var makeID: @Sendable () -> UUID = { UUID() }

    func execute(_ question: String) async throws(AppError) -> QuestionAnswer {
        let results = try await search.execute(question, filters: SearchFilters())
        let context = ScriptureAIPrompt.context(for: Self.interleaved(results))
        let explanation = await explain(question, results: results, context: context)
        return QuestionAnswer(id: makeID(), question: question, results: results,
                              contextPassages: context, explanation: explanation)
    }

    private func explain(_ question: String, results: SearchResults, context: [ScripturePassage]) async -> AIExplanationOutcome {
        guard !results.isEmpty else { return .notAttempted }
        guard await preferences.isEnabled() else { return .disabled }
        if case .unavailable(let reason) = await ai.availability() { return .unavailable(reason: reason) }
        let response: ScriptureAIResponse
        do {
            response = try await ai.answer(question: question, passages: context)
        } catch {
            Log.ai.error("Generation failed (\(ai.providerName, privacy: .public)): \(String(describing: error), privacy: .public)")
            return .failed(String(localized: "An AI explanation couldn’t be generated this time. The passages are unaffected."))
        }
        switch AIResponseValidator.validate(response, passages: context) {
        case .success(let validated):
            if validated.removedSentenceCount > 0 {
                Log.ai.notice("Validator removed \(validated.removedSentenceCount) unverifiable sentence(s)")
            }
            return .explanation(validated)
        case .failure(let rejection):
            Log.ai.notice("Explanation withheld: \(String(describing: rejection), privacy: .public)")
            return .failed(String(localized: "The AI explanation was withheld because it couldn’t be verified against the passages."))
        }
    }

    /// Best of each tradition first (in relevance order), then each tradition's second best, and so on,
    /// so a small context still spans traditions.
    static func interleaved(_ results: SearchResults) -> [ScripturePassage] {
        let groups = results.groups.sorted { lhs, rhs in
            let l = lhs.results.first, r = rhs.results.first
            if l?.matchedAllTerms != r?.matchedAllTerms { return l?.matchedAllTerms == true }
            return (l?.score ?? 0) > (r?.score ?? 0)
        }
        var ordered: [ScripturePassage] = []
        let depth = groups.map(\.results.count).max() ?? 0
        for rank in 0..<depth {
            for group in groups where rank < group.results.count {
                ordered.append(group.results[rank].passage)
            }
        }
        return ordered
    }
}
