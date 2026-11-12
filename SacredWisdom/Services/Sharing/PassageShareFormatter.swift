import Foundation

/// Builds the plain text shared for a passage. Scripture is copied verbatim, and every source used is credited
/// with its license (some, like Tanzil, permit redistribution only verbatim and with attribution).
enum PassageShareFormatter {
    static func text(for passage: ScripturePassage, collectionName: String, translationID: String?) -> String {
        let translation = passage.text(preferring: translationID)
        var lines = ["\(passage.reference) · \(collectionName)", ""]
        if let original = passage.originalText {
            lines += [original, ""]
        }
        if let translation {
            lines += [translation.text, "— \(translation.translation.name)", ""]
        }
        if let translation {
            lines.append("\(translation.translation.source.attribution) \(translation.translation.source.license).")
        }
        if passage.originalText != nil, let source = passage.originalSource, source.id != translation?.translation.source.id {
            lines.append("Original text: \(source.attribution) \(source.license).")
        }
        lines.append("Shared from Sacred Wisdom")
        return lines.joined(separator: "\n")
    }
}
