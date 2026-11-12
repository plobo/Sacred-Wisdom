import Foundation

/// Folds text for matching. Used on both indexed content and user queries so they meet in the middle.
/// Never applied to text that is displayed: scripture is always shown verbatim.
enum SearchTextNormalizer {
    static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.precomposedStringWithCompatibilityMapping.unicodeScalars {
            switch scalar.value {
            // Hebrew cantillation marks and vowel points.
            case 0x0591...0x05BD, 0x05BF, 0x05C1, 0x05C2, 0x05C4, 0x05C5, 0x05C7:
                continue
            // Hebrew maqaf and sof pasuq separate words.
            case 0x05BE, 0x05C3:
                scalars.append(" ")
            // Arabic harakat, Quranic annotation marks, superscript alef, tatweel.
            case 0x0610...0x061A, 0x064B...0x065F, 0x0670, 0x06D6...0x06DC, 0x06DF...0x06E8, 0x06EA...0x06ED, 0x0640:
                continue
            // Alef with madda / hamza above / hamza below / wasla → bare alef.
            case 0x0622, 0x0623, 0x0625, 0x0671:
                scalars.append("\u{0627}")
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars).lowercased()
    }

    /// Splits normalized text into words the same way the FTS5 unicode61 tokenizer does (approximately).
    static func words(in text: String) -> [String] {
        text.split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }
}
