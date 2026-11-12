import Foundation
import Testing
@testable import SacredWisdom

/// Structural fixtures only. These are not scripture and are never shown as such.
enum Fixtures {
    static let source = ContentSource(id: "src", name: "Fixture", url: nil, license: "N/A", attribution: "Test fixture")

    static func religion(_ id: String, order: Int) -> Religion {
        Religion(id: id, name: id.capitalized, summary: "", emblem: "•", tintKey: "", sortOrder: order)
    }

    static func collection(_ id: String, religion: String, availability: ScriptureCollection.Availability = .bundled) -> ScriptureCollection {
        ScriptureCollection(id: id, religionID: religion, name: id, structureDescription: "", languages: ["en"],
                            availability: availability, originalLanguage: "en", originalSource: nil,
                            defaultTranslationID: "\(id)-t")
    }

    static func translation(_ id: String, collection: String = "c1") -> Translation {
        Translation(id: id, collectionID: collection, name: id.uppercased(), languageCode: "en",
                    translator: "Fixture", year: nil, source: source)
    }

    static func passage(_ id: String, religion: String = "r1") -> ScripturePassage {
        ScripturePassage(
            id: id, religionID: religion, collectionID: "c1", bookID: "b1", sectionID: "s1", sequence: 1,
            reference: "TEST \(id)", originalLanguage: "en", originalText: nil, originalSource: nil,
            texts: [PassageText(translation: translation("t1"), text: "[fixture text]")]
        )
    }

    /// Two religions; c1 has two books (declared out of order) and two translations; c2 has one passage.
    /// c1 reading order: p1, p2, p3, p4.
    /// Themes: p1 [th1], p3 [th1, th2], p4 [th2] in r1; p5 [th2, th1] in r2; p2 none.
    static var libraryJSON: [String: Any] { [
        "schemaVersion": 3,
        "themes": [["id": "th1", "name": "Theme One"], ["id": "th2", "name": "Theme Two"]],
        "religions": [
            ["id": "r2", "name": "R2", "summary": "", "emblem": "•", "tintKey": "", "sortOrder": 1],
            ["id": "r1", "name": "R1", "summary": "", "emblem": "•", "tintKey": "", "sortOrder": 0],
        ],
        "sources": [["id": "src", "name": "Fixture", "url": NSNull(), "license": "N/A", "attribution": "Test fixture"]],
        "collections": [
            ["id": "c1", "religionID": "r1", "name": "C1", "structureDescription": "", "languages": ["ar", "en"],
             "availability": "bundled", "originalLanguage": "ar", "originalSourceID": "src", "defaultTranslationID": "t1"],
            ["id": "c2", "religionID": "r2", "name": "C2", "structureDescription": "", "languages": ["en"],
             "availability": "bundled", "originalLanguage": "en", "originalSourceID": NSNull(), "defaultTranslationID": "t3"],
        ],
        "translations": [
            ["id": "t1", "collectionID": "c1", "name": "T1", "languageCode": "en", "translator": "x", "year": NSNull(), "sourceID": "src"],
            ["id": "t2", "collectionID": "c1", "name": "T2", "languageCode": "en", "translator": "x", "year": 1900, "sourceID": "src"],
            ["id": "t3", "collectionID": "c2", "name": "T3", "languageCode": "en", "translator": "x", "year": NSNull(), "sourceID": "src"],
        ],
        "books": [
            ["id": "b2", "collectionID": "c1", "title": "B2", "division": NSNull(), "sequence": 2],
            ["id": "b1", "collectionID": "c1", "title": "B1", "division": "D", "sequence": 1],
            ["id": "b3", "collectionID": "c2", "title": "B3", "division": NSNull(), "sequence": 1],
        ],
        "sections": [
            ["id": "s1b", "bookID": "b1", "title": "S1b", "sequence": 2],
            ["id": "s1a", "bookID": "b1", "title": "S1a", "sequence": 1],
            ["id": "s2a", "bookID": "b2", "title": "S2a", "sequence": 1],
            ["id": "s3a", "bookID": "b3", "title": "S3a", "sequence": 1],
        ],
        "passages": [
            ["id": "p4", "sectionID": "s2a", "sequence": 1, "reference": "REF 4", "originalText": "[o4]", "texts": ["t2": "[t2-4]", "t1": "[t1-4]"], "themes": ["th2"]],
            ["id": "p2", "sectionID": "s1a", "sequence": 2, "reference": "REF 2", "originalText": NSNull(), "texts": ["t1": "[t1-2]"]],
            ["id": "p1", "sectionID": "s1a", "sequence": 1, "reference": "REF 1", "originalText": "[o1]", "texts": ["t1": "[t1-1]", "t2": "[t2-1]"], "themes": ["th1"]],
            ["id": "p3", "sectionID": "s1b", "sequence": 1, "reference": "REF 3", "originalText": NSNull(), "texts": ["t1": "[t1-3]"], "themes": ["th1", "th2"]],
            ["id": "p5", "sectionID": "s3a", "sequence": 1, "reference": "REF 5", "originalText": NSNull(), "texts": ["t3": "[t3-5]"], "themes": ["th2", "th1"]],
        ],
    ] }

    static func libraryDTO(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> SampleLibraryDTO {
        var json = libraryJSON
        mutate(&json)
        return try SampleLibraryDTO.decode(from: JSONSerialization.data(withJSONObject: json))
    }

    static func repository() throws -> SampleLibraryRepository {
        try SampleLibraryRepository(library: libraryDTO())
    }
}

struct StubReligionRepository: ReligionRepository {
    var religions: [Religion] = []
    var collections: [ScriptureCollection] = []
    var error: AppError?

    func fetchReligions() async throws(AppError) -> [Religion] {
        if let error { throw error }
        return religions
    }

    func fetchCollections() async throws(AppError) -> [ScriptureCollection] {
        if let error { throw error }
        return collections
    }
}

struct StubPassageRepository: PassageRepository {
    var daily: ScripturePassage?
    var error: AppError?

    func dailyPassage(on date: Date) async throws(AppError) -> ScripturePassage? {
        if let error { throw error }
        return daily
    }
}

struct StubRecentPassages: LoadRecentPassagesUseCaseProtocol {
    var passages: [ScripturePassage] = []
    func execute(limit: Int) async throws(AppError) -> [ScripturePassage] { Array(passages.prefix(limit)) }
}

/// In-memory reading history for use-case and view-model tests.
actor StubReadingHistory: ReadingHistoryRepository {
    private(set) var items: [ReadingHistoryItem] = []
    var failure: AppError?

    init(passageIDs: [String] = [], failure: AppError? = nil) {
        items = passageIDs.enumerated().map { ReadingHistoryItem(passageID: $1, viewedAt: Date(timeIntervalSince1970: Double(-$0))) }
        self.failure = failure
    }

    func record(passageID: String, at date: Date) throws(AppError) {
        if let failure { throw failure }
        items.removeAll { $0.passageID == passageID }
        items.insert(ReadingHistoryItem(passageID: passageID, viewedAt: date), at: 0)
    }

    func recent(limit: Int) throws(AppError) -> [ReadingHistoryItem] {
        if let failure { throw failure }
        return Array(items.prefix(max(limit, 0)))
    }

    func clear() throws(AppError) {
        if let failure { throw failure }
        items = []
    }
}

struct StubDashboardUseCase: LoadHomeDashboardUseCaseProtocol {
    var result: Result<HomeDashboard, AppError>

    func execute(on date: Date) async throws(AppError) -> HomeDashboard {
        try result.get()
    }
}

extension Fixtures {
    static func libraryData(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var json = libraryJSON
        mutate(&json)
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    /// A migrated in-memory database with the fixture package imported.
    static func database() async throws -> DatabaseManager {
        let manager = DatabaseManager(location: .inMemory, bundledPackages: [])
        try await ContentImporter(database: manager.connection()).importPackage(id: "fixture", data: libraryData())
        return manager
    }
}

typealias LibraryRepository = ReligionRepository & ScriptureRepository & PassageRepository & RelatedPassageRepository

/// Both repository implementations must behave identically; contract tests run against each.
enum RepositoryKind: String, CaseIterable, CustomTestStringConvertible, Sendable {
    case inMemory, sqlite

    var testDescription: String { rawValue }

    func make() async throws -> any LibraryRepository {
        switch self {
        case .inMemory: try Fixtures.repository()
        case .sqlite: SQLiteScriptureRepository(database: try await Fixtures.database())
        }
    }
}

/// In-memory history double for view model tests (the SwiftData store is tested separately).
actor StubSearchHistory: SearchHistoryRepository {
    private(set) var items: [SearchHistoryItem] = []

    func recent(limit: Int) -> [SearchHistoryItem] { Array(items.prefix(max(limit, 0))) }

    func record(_ query: String, at date: Date) {
        items.removeAll { $0.query == query }
        items.insert(SearchHistoryItem(id: UUID(), query: query, searchedAt: date), at: 0)
    }

    func remove(id: UUID) { items.removeAll { $0.id == id } }
    func clear() { items = [] }
}

struct FailingSearchRepository: ScriptureSearchRepository {
    func search(query: SearchQuery, filters: SearchFilters) async throws(AppError) -> [ScriptureSearchResult] {
        throw .unexpected("semantic offline")
    }
}

struct FixedSearchRepository: ScriptureSearchRepository {
    let results: [ScriptureSearchResult]
    func search(query: SearchQuery, filters: SearchFilters) async throws(AppError) -> [ScriptureSearchResult] { results }
}

extension Fixtures {
    static func keywordSearch() async throws -> LocalKeywordSearchRepository {
        let database = try await database()
        return LocalKeywordSearchRepository(index: FullTextSearchIndex(database: database),
                                            scripture: SQLiteScriptureRepository(database: database))
    }

    static func searchUseCase() async throws -> SearchScriptureUseCase {
        let database = try await database()
        let sqlite = SQLiteScriptureRepository(database: database)
        return SearchScriptureUseCase(
            search: LocalKeywordSearchRepository(index: FullTextSearchIndex(database: database), scripture: sqlite),
            religions: sqlite
        )
    }
}

extension Fixtures {
    /// Real SwiftData repositories over a fresh in-memory store.
    @MainActor
    static func userData(now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_000) }) throws -> UserDataContext {
        let container = try PersistenceManager.makeContainer(location: .inMemory)
        return UserDataContext(
            bookmarks: SwiftDataBookmarkRepository(modelContainer: container),
            history: SwiftDataReadingHistoryRepository(modelContainer: container),
            changes: UserDataChanges(),
            now: now
        )
    }

    /// A unique on-disk store location, for persistence tests. Delete with `PersistenceManager.deleteStore`.
    static func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sw-test-\(UUID().uuidString).store")
    }
}

/// Always fails writes, for error-path tests.
struct FailingBookmarkRepository: BookmarkRepository {
    var error: AppError = .userData("write failed")
    func bookmarks() async throws(AppError) -> [Bookmark] { throw error }
    func bookmark(passageID: String) async throws(AppError) -> Bookmark? { nil }
    func bookmarkedPassageIDs() async throws(AppError) -> Set<String> { [] }
    func addBookmark(passageID: String, at date: Date) async throws(AppError) -> Bookmark { throw error }
    func removeBookmark(passageID: String) async throws(AppError) { throw error }
    func setNote(_ note: String, passageID: String, at date: Date) async throws(AppError) -> Bookmark { throw error }
    func moveBookmark(passageID: String, toCollection collectionID: UUID?) async throws(AppError) { throw error }
    func collections() async throws(AppError) -> [BookmarkCollection] { [] }
    func createCollection(named name: String, at date: Date) async throws(AppError) -> BookmarkCollection { throw error }
    func renameCollection(id: UUID, to name: String) async throws(AppError) { throw error }
    func deleteCollection(id: UUID) async throws(AppError) { throw error }
}
