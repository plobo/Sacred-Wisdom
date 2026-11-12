import Foundation

/// A future online model (e.g. via OpenRouter). Sends prompt text, returns the model's raw reply.
/// No implementation ships: the app makes no network requests, and remote AI must never be required.
protocol RemoteAIProvider: Sendable {
    var name: String { get }
    var isConfigured: Bool { get }
    func complete(system: String, user: String) async throws(AppError) -> String
}

/// Adapts any `RemoteAIProvider` to `ScriptureAIService` with the same instructions as the on-device model.
/// The provider is asked for JSON: {"explanation": "...", "citedPassages": [1, 2]}.
struct RemoteScriptureAIService: ScriptureAIService {
    let provider: any RemoteAIProvider
    let religions: any ReligionRepository

    var providerName: String { provider.name }

    func availability() async -> AIAvailability {
        provider.isConfigured ? .available : .unavailable(reason: String(localized: "No online AI provider is set up."))
    }

    func answer(question: String, passages: [ScripturePassage]) async throws(AppError) -> ScriptureAIResponse {
        let system = ScriptureAIPrompt.instructions + """

            Reply with JSON only: {"explanation": string, "citedPassages": [numbers]}.
            """
        let user = ScriptureAIPrompt.prompt(question: question, passages: passages,
                                            religionNames: try await ScriptureAIPrompt.religionNames(religions))
        let reply = try await provider.complete(system: system, user: user)
        return try Self.parse(reply, providerName: provider.name)
    }

    struct Payload: Decodable {
        let explanation: String
        let citedPassages: [Int]?
    }

    /// Accepts the JSON object alone or wrapped in prose / code fences.
    static func parse(_ reply: String, providerName: String) throws(AppError) -> ScriptureAIResponse {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(reply[start...end].utf8)) else {
            throw .unexpected("Unreadable AI reply")
        }
        return ScriptureAIResponse(explanation: payload.explanation, citedPassageNumbers: payload.citedPassages ?? [],
                                   providerName: providerName)
    }
}

/// No AI at all: the documented non-AI fallback.
struct UnavailableScriptureAIService: ScriptureAIService {
    let reason: String
    let providerName = "None"

    func availability() async -> AIAvailability { .unavailable(reason: reason) }

    func answer(question: String, passages: [ScripturePassage]) async throws(AppError) -> ScriptureAIResponse {
        throw .unexpected(reason)
    }
}

/// Returns a fixed reply. Used by UI tests (no model in automation) and unit tests.
struct ScriptedScriptureAIService: ScriptureAIService {
    let explanation: String
    let citedPassageNumbers: [Int]
    let providerName = "Scripted test model"

    func availability() async -> AIAvailability { .available }

    func answer(question: String, passages: [ScripturePassage]) async throws(AppError) -> ScriptureAIResponse {
        ScriptureAIResponse(explanation: explanation, citedPassageNumbers: citedPassageNumbers, providerName: providerName)
    }
}

/// UserDefaults-backed AI preference. AI explanations are on by default when available; users can turn them off.
struct UserDefaultsAIPreferenceStore: AIPreferenceStore {
    static let key = "aiExplanationsEnabled"
    nonisolated(unsafe) let defaults: UserDefaults

    func isEnabled() async -> Bool { defaults.object(forKey: Self.key) as? Bool ?? true }
    func setEnabled(_ enabled: Bool) async { defaults.set(enabled, forKey: Self.key) }
}

actor InMemoryAIPreferenceStore: AIPreferenceStore {
    private var enabled: Bool
    init(enabled: Bool = true) { self.enabled = enabled }
    func isEnabled() -> Bool { enabled }
    func setEnabled(_ enabled: Bool) { self.enabled = enabled }
}
