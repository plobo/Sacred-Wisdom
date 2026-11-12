import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device Foundation Models (iOS 26+). Works offline and needs no API key. On older systems or
/// ineligible devices it reports itself unavailable and the app shows passages without an explanation.
struct FoundationModelsScriptureAIService: ScriptureAIService {
    let providerName = String(localized: "Apple on-device model")
    let religions: any ReligionRepository

    func availability() async -> AIAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return OnDeviceModel.availability()
        }
        #endif
        return .unavailable(reason: String(localized: "AI explanations need iOS 26 or later."))
    }

    func answer(question: String, passages: [ScripturePassage]) async throws(AppError) -> ScriptureAIResponse {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let prompt = ScriptureAIPrompt.prompt(question: question, passages: passages,
                                                  religionNames: try await ScriptureAIPrompt.religionNames(religions))
            let generated = try await OnDeviceModel.generate(prompt: prompt)
            return ScriptureAIResponse(explanation: generated.explanation, citedPassageNumbers: generated.citedPassages,
                                       providerName: providerName)
        }
        #endif
        throw .unexpected("Foundation Models unavailable")
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedScriptureAnswer {
    @Guide(description: "A brief, neutral explanation of what the numbered passages say, citing them like [1].")
    var explanation: String
    @Guide(description: "The numbers of the passages the explanation relies on.")
    var citedPassages: [Int]
}

@available(iOS 26.0, *)
enum OnDeviceModel {
    static func availability() -> AIAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: String(localized: "This device doesn’t support Apple Intelligence."))
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: String(localized: "Turn on Apple Intelligence in Settings to get AI explanations."))
        case .unavailable(.modelNotReady):
            return .unavailable(reason: String(localized: "The on-device model is still downloading."))
        case .unavailable:
            return .unavailable(reason: String(localized: "The on-device model isn’t available right now."))
        }
    }

    static func generate(prompt: String) async throws(AppError) -> GeneratedScriptureAnswer {
        let session = LanguageModelSession(instructions: ScriptureAIPrompt.instructions)
        do {
            let response = try await session.respond(
                to: prompt, generating: GeneratedScriptureAnswer.self,
                options: GenerationOptions(temperature: 0.2)
            )
            return response.content
        } catch {
            throw .unexpected("On-device generation failed: \(error)")
        }
    }
}
#endif
