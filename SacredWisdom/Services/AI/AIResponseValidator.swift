import Foundation
import NaturalLanguage

/// Checks AI output against the passages it was given, sentence by sentence. A sentence is removed if it
/// * cites a passage number that was not provided,
/// * quotes text (in double or curly quotes) that does not appear in any provided passage, or
/// * names a chapter:verse style reference that is not one of the provided passages.
/// The explanation is rejected outright if nothing remains or it cites no provided passage.
enum AIResponseValidator {
    static let maximumLength = 1_500

    enum Rejection: Error, Equatable {
        case empty
        case noValidCitations
    }

    static func validate(
        _ response: ScriptureAIResponse,
        passages: [ScripturePassage]
    ) -> Result<ValidatedExplanation, Rejection> {
        let range = 1...max(passages.count, 1)
        let corpus = passages.flatMap { passage in
            ([passage.originalText].compactMap { $0 } + passage.texts.map(\.text)).map(normalizeForQuote)
        }
        let references = Set(passages.map(\.reference))

        var kept: [String] = []
        var removed = 0
        var inlineCitations: [Int] = []
        for sentence in sentences(in: response.explanation) {
            let markers = citationMarkers(in: sentence)
            let quotes = quotedSpans(in: sentence)
            let mentioned = referenceMentions(in: sentence)
            let valid = !passages.isEmpty
                && markers.allSatisfy(range.contains)
                && quotes.allSatisfy { quote in corpus.contains { $0.contains(normalizeForQuote(quote)) } }
                && mentioned.allSatisfy { mention in references.contains { $0.hasPrefix(mention) || mention.hasPrefix($0) } }
            if valid {
                kept.append(sentence)
                inlineCitations += markers
            } else {
                removed += 1
            }
        }

        var text = kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        if text.count > maximumLength { text = String(text.prefix(maximumLength)) + "…" }

        var numbers: [Int] = []
        for number in inlineCitations + response.citedPassageNumbers where range.contains(number) && number <= passages.count {
            if !numbers.contains(number) { numbers.append(number) }
        }
        guard !numbers.isEmpty else { return .failure(.noValidCitations) }
        let citations = numbers.sorted().map { number in
            AICitation(number: number, passageID: passages[number - 1].id, reference: passages[number - 1].reference)
        }
        return .success(ValidatedExplanation(text: text, citations: citations, providerName: response.providerName,
                                             removedSentenceCount: removed))
    }

    // MARK: Parsing

    static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
            return true
        }
        return result
    }

    /// "[3]" and "[1, 4]" markers.
    static func citationMarkers(in sentence: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d+(?:\s*,\s*\d+)*)\]"#) else { return [] }
        let ns = sentence as NSString
        return regex.matches(in: sentence, range: NSRange(location: 0, length: ns.length)).flatMap { match in
            ns.substring(with: match.range(at: 1)).split(separator: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespaces))
            }
        }
    }

    /// Text inside “curly” or "straight" double quotes. Single quotes are ignored (apostrophes).
    static func quotedSpans(in sentence: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"[“"]([^”"]+)[”"]"#) else { return [] }
        let ns = sentence as NSString
        return regex.matches(in: sentence, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// "Matthew 5:9", "1 John 4:8", "Bhagavad Gita 2.47", "Psalms 23:1".
    static func referenceMentions(in sentence: String) -> [String] {
        let pattern = #"(?:[1-3]\s)?[A-Z][A-Za-z'-]+(?:\s[A-Z][A-Za-z'-]+)?\s\d+[:.]\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = sentence as NSString
        return regex.matches(in: sentence, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// Case-, diacritic- and punctuation-insensitive form used to compare quotations with scripture.
    static func normalizeForQuote(_ text: String) -> String {
        SearchTextNormalizer.words(in: SearchTextNormalizer.normalize(text)
            .folding(options: .diacriticInsensitive, locale: nil)).joined(separator: " ")
    }
}
