import Foundation

/// The text of a passage in one translation.
struct PassageText: Hashable, Sendable {
    let translation: Translation
    let text: String
}

/// A single passage of verified scripture. Never constructed from AI output.
struct ScripturePassage: Identifiable, Hashable, Sendable {
    /// Stable identifier, independent of translation (e.g. "bible.matthew.5.9").
    let id: String
    let religionID: String
    let collectionID: String
    let bookID: String
    let sectionID: String
    /// Order within its section.
    let sequence: Int
    /// Human-readable reference taken verbatim from source data, e.g. "Matthew 5:9".
    let reference: String
    let originalLanguage: String
    let originalText: String?
    let originalSource: ContentSource?
    /// Available translations, with the collection's default translation first.
    let texts: [PassageText]

    /// The text in the requested translation, falling back to the default translation.
    func text(preferring translationID: String?) -> PassageText? {
        texts.first { $0.translation.id == translationID } ?? texts.first
    }
}
