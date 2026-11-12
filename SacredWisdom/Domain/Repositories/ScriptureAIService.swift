import Foundation

/// Generates a neutral explanation of *provided* passages. Implementations never retrieve scripture and
/// their output is always validated before display (`AIResponseValidator`).
protocol ScriptureAIService: Sendable {
    var providerName: String { get }
    func availability() async -> AIAvailability
    func answer(question: String, passages: [ScripturePassage]) async throws(AppError) -> ScriptureAIResponse
}

/// Whether the user wants AI explanations. AI is optional; search never depends on it.
protocol AIPreferenceStore: Sendable {
    func isEnabled() async -> Bool
    func setEnabled(_ enabled: Bool) async
}
