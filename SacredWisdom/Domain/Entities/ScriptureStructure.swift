import Foundation

/// Top level of a collection's flexible hierarchy: a book (Matthew), text (Dhammapada) or bani (Japji Sahib).
struct ScriptureBook: Identifiable, Hashable, Sendable {
    let id: String
    let collectionID: String
    let title: String
    /// Optional grouping label, e.g. "New Testament" or "Ketuvim".
    let division: String?
    let sequence: Int
}

/// Second level: chapter, surah, psalm, vagga or ang.
struct ScriptureSection: Identifiable, Hashable, Sendable {
    let id: String
    let bookID: String
    let collectionID: String
    let title: String
    let sequence: Int
}
