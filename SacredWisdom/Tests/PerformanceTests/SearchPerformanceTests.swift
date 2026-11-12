import Foundation
import XCTest
@testable import SacredWisdom

/// Performance at a realistic full-library scale. The corpus is synthetic filler (deterministic word
/// sequences), never presented as scripture; only its size matters here.
final class SearchPerformanceTests: XCTestCase {
    static let collectionCount = 6
    static let passagesPerCollection = 2_000

    /// ~12,000 passages, two translations each (24,000 indexed texts).
    static func syntheticLibrary() throws -> Data {
        let vocabulary = ["light", "path", "river", "stone", "mercy", "peace", "mountain", "word", "seed", "fire",
                          "water", "heart", "truth", "shepherd", "garden", "voice", "silence", "wisdom", "star", "road"]
        var religions: [[String: Any]] = [], collections: [[String: Any]] = [], translations: [[String: Any]] = []
        var books: [[String: Any]] = [], sections: [[String: Any]] = [], passages: [[String: Any]] = []
        var seed: UInt64 = 42
        func next() -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) }
        for c in 0..<collectionCount {
            religions.append(["id": "r\(c)", "name": "R\(c)", "summary": "", "emblem": "•", "tintKey": "", "sortOrder": c])
            collections.append(["id": "c\(c)", "religionID": "r\(c)", "name": "C\(c)", "structureDescription": "",
                                "languages": ["en"], "availability": "bundled", "originalLanguage": "en",
                                "originalSourceID": NSNull(), "defaultTranslationID": "c\(c)-a"])
            for t in ["a", "b"] {
                translations.append(["id": "c\(c)-\(t)", "collectionID": "c\(c)", "name": "T\(t)", "languageCode": "en",
                                     "translator": "synthetic", "year": NSNull(), "sourceID": "src"])
            }
            books.append(["id": "c\(c)-b", "collectionID": "c\(c)", "title": "Book \(c)", "division": NSNull(), "sequence": 1])
            for s in 0..<(passagesPerCollection / 50) {
                sections.append(["id": "c\(c)-s\(s)", "bookID": "c\(c)-b", "title": "Section \(s)", "sequence": s])
            }
            for p in 0..<passagesPerCollection {
                func sentence() -> String { (0..<18).map { _ in vocabulary[next() % vocabulary.count] }.joined(separator: " ") }
                passages.append(["id": "c\(c)-p\(p)", "sectionID": "c\(c)-s\(p / 50)", "sequence": p % 50,
                                 "reference": "SYN \(c).\(p)", "originalText": NSNull(),
                                 "texts": ["c\(c)-a": sentence(), "c\(c)-b": sentence()]])
            }
        }
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 3, "religions": religions,
            "sources": [["id": "src", "name": "Synthetic", "url": NSNull(), "license": "N/A", "attribution": "Synthetic"]],
            "collections": collections, "translations": translations, "books": books, "sections": sections,
            "passages": passages, "themes": [],
        ])
    }

    private static let shared: (SearchScriptureUseCase, DatabaseManager)? = {
        let url = FileManager.default.temporaryDirectory.appending(path: "perf-library.json")
        guard let data = try? syntheticLibrary(), (try? data.write(to: url)) != nil else { return nil }
        let database = DatabaseManager(location: .inMemory, bundledPackages: [.init(id: "perf", url: url)])
        let sqlite = SQLiteScriptureRepository(database: database)
        let search = SearchScriptureUseCase(
            search: LocalKeywordSearchRepository(index: FullTextSearchIndex(database: database), scripture: sqlite),
            religions: sqlite)
        return (search, database)
    }()

    private func run(_ block: @escaping @Sendable () async throws -> Void) {
        let done = expectation(description: "done")
        Task {
            try? await block()
            done.fulfill()
        }
        wait(for: [done], timeout: 60)
    }

    private func useCase() throws -> SearchScriptureUseCase {
        let shared = try XCTUnwrap(Self.shared)
        run { _ = try await shared.1.connection() } // import outside the measured block
        return shared.0
    }

    /// A broad query: every collection matches; results are capped at 100 passages.
    func testBroadKeywordSearch() throws {
        let search = try useCase()
        measure(metrics: [XCTClockMetric()]) {
            run { _ = try await search.execute("mercy", filters: SearchFilters()) }
        }
    }

    /// A question with several keywords and the any-word fallback.
    func testQuestionSearch() throws {
        let search = try useCase()
        measure(metrics: [XCTClockMetric()]) {
            run { _ = try await search.execute("What is said about the shepherd by the river?", filters: SearchFilters()) }
        }
    }

    /// Budget for interactive search on the full-size corpus (simulator, debug build).
    func testSearchStaysInteractive() throws {
        let search = try useCase()
        let start = ContinuousClock.now
        run {
            for query in ["mercy", "peace path", "\"light river\"", "What gives wisdom?"] {
                let results = try await search.execute(query, filters: SearchFilters())
                XCTAssertFalse(results.isEmpty, query)
            }
        }
        let elapsed = ContinuousClock.now - start
        print("4 searches over 12,000 passages: \(elapsed)")
        XCTAssertLessThan(elapsed, .seconds(1), "average search should stay under 250 ms")
    }
}
