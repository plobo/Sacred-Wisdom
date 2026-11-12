import Foundation

/// Where the reader opens.
enum ReaderStart: Hashable, Sendable {
    case passage(String)
    case section(String)
}

enum PassageDirection: Sendable {
    case previous, next
}

/// Everything the reader shows for one passage.
struct ReaderPage: Equatable, Sendable {
    let collection: ScriptureCollection
    let book: ScriptureBook
    let section: ScriptureSection
    let passage: ScripturePassage
    let translations: [Translation]
    let previousPassageID: String?
    let nextPassageID: String?
}

/// A collection's browsable table of contents.
struct CollectionContents: Equatable, Sendable {
    struct BookEntry: Equatable, Sendable, Identifiable {
        let book: ScriptureBook
        let sections: [ScriptureSection]
        var id: String { book.id }
    }

    let collection: ScriptureCollection
    let translations: [Translation]
    let books: [BookEntry]
}
