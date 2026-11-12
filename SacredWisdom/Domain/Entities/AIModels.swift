import Foundation

enum AIAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

/// Raw output from an AI provider, before validation. Passage numbers are 1-based positions in the
/// list of passages the provider was given.
struct ScriptureAIResponse: Equatable, Sendable {
    let explanation: String
    let citedPassageNumbers: [Int]
    let providerName: String
}

/// A cited source, as shown under an explanation: "[2] Dhammapada 5".
struct AICitation: Equatable, Hashable, Sendable, Identifiable {
    let number: Int
    let passageID: String
    let reference: String

    var id: Int { number }
}

/// An explanation that passed validation: every citation is a retrieved passage and every quotation
/// is verbatim from one.
struct ValidatedExplanation: Equatable, Sendable {
    let text: String
    let citations: [AICitation]
    let providerName: String
    /// Sentences removed because they could not be verified (shown as a note, never silently).
    let removedSentenceCount: Int
}

enum AIExplanationOutcome: Equatable, Sendable {
    case explanation(ValidatedExplanation)
    /// The user turned AI explanations off.
    case disabled
    case unavailable(reason: String)
    /// Generation failed or nothing verifiable remained.
    case failed(String)
    /// No passages were found, so nothing was asked of the AI.
    case notAttempted
}

/// One answered question: verified passages first, AI explanation (if any) alongside, never mixed.
struct QuestionAnswer: Equatable, Sendable, Identifiable {
    let id: UUID
    let question: String
    let results: SearchResults
    /// The passages given to the AI, numbered from 1 in this order.
    let contextPassages: [ScripturePassage]
    let explanation: AIExplanationOutcome
}
