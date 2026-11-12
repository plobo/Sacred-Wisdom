import Foundation

/// Where a piece of scripture text came from, and under what terms it is redistributed.
struct ContentSource: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL?
    let license: String
    let attribution: String
}

/// A translation of a collection into a language.
struct Translation: Identifiable, Hashable, Sendable {
    let id: String
    let collectionID: String
    let name: String
    let languageCode: String
    let translator: String
    let year: Int?
    let source: ContentSource
}
