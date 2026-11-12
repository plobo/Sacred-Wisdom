import Foundation

/// The instructions and context given to any AI provider. The same rules apply on device and remotely.
enum ScriptureAIPrompt {
    /// Context budget: passages beyond this are not sent, and long passages are shortened for the prompt only.
    static let maximumPassages = 8
    static let maximumCharactersPerPassage = 700

    static let instructions = """
        You help people explore what sacred texts from different traditions say about a question.
        You are given numbered passages retrieved from a verified library. Rules:
        - Use only the numbered passages. Do not use outside knowledge of scripture.
        - Cite passages with their number in square brackets, for example [2].
        - Do not quote words that are not in a passage. Prefer describing over quoting.
        - Do not mention any scripture reference that is not in the list.
        - Be neutral and brief (at most 5 sentences). Describe what each tradition's passage says.
        - Do not rank traditions, claim they agree or disagree beyond what the passages say, or present an
          interpretation as universal fact. Use wording like "this passage speaks of".
        """

    static func religionNames(_ religions: any ReligionRepository) async throws(AppError) -> [String: String] {
        Dictionary(try await religions.fetchReligions().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    static func context(for passages: [ScripturePassage]) -> [ScripturePassage] {
        Array(passages.prefix(maximumPassages))
    }

    static func prompt(question: String, passages: [ScripturePassage], religionNames: [String: String]) -> String {
        var lines = ["Question: \(question)", "", "Passages:"]
        for (index, passage) in passages.enumerated() {
            let text = passage.texts.first.map { String($0.text.prefix(maximumCharactersPerPassage)) } ?? ""
            let tradition = religionNames[passage.religionID] ?? passage.religionID
            let translation = passage.texts.first?.translation.name ?? ""
            lines.append("[\(index + 1)] \(passage.reference) (\(tradition), \(translation)): \(text)")
        }
        lines += ["", "Write a short, neutral explanation that cites the passages by number."]
        return lines.joined(separator: "\n")
    }
}
