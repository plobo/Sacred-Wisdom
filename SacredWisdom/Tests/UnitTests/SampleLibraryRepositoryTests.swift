import Foundation
import Testing
@testable import SacredWisdom

/// Behaviour every scripture repository must share (in-memory reference and SQLite).
@Suite struct ScriptureRepositoryContractTests {
    @Test(arguments: RepositoryKind.allCases)
    func religionsAndCollectionsInDisplayOrder(kind: RepositoryKind) async throws {
        let repo = try await kind.make()
        #expect(try await repo.fetchReligions().map(\.id) == ["r1", "r2"])
        #expect(Set(try await repo.fetchCollections().map(\.id)) == ["c1", "c2"])
        let c1 = try await repo.collection(id: "c1")
        #expect(c1.languages == ["ar", "en"])
        #expect(c1.originalSource?.id == "src")
        #expect(c1.defaultTranslationID == "t1")
        #expect(try await repo.collection(id: "c2").originalSource == nil)
    }

    @Test(arguments: RepositoryKind.allCases)
    func structureIsSortedBySequence(kind: RepositoryKind) async throws {
        let repo = try await kind.make()
        #expect(try await repo.books(collectionID: "c1").map(\.id) == ["b1", "b2"])
        #expect(try await repo.book(id: "b1").division == "D")
        #expect(try await repo.sections(bookID: "b1").map(\.id) == ["s1a", "s1b"])
        #expect(try await repo.section(id: "s1b").collectionID == "c1")
        #expect(try await repo.passages(sectionID: "s1a").map(\.id) == ["p1", "p2"])
        #expect(try await repo.translations(collectionID: "c1").map(\.id) == ["t1", "t2"])
    }

    @Test(arguments: RepositoryKind.allCases)
    func passageResolvesHierarchyAndOriginal(kind: RepositoryKind) async throws {
        let passage = try await kind.make().passage(id: "p1")
        #expect(passage.religionID == "r1")
        #expect(passage.collectionID == "c1")
        #expect(passage.bookID == "b1")
        #expect(passage.sectionID == "s1a")
        #expect(passage.sequence == 1)
        #expect(passage.reference == "REF 1")
        #expect(passage.originalLanguage == "ar")
        #expect(passage.originalText == "[o1]")
        #expect(passage.originalSource?.id == "src")
    }

    @Test(arguments: RepositoryKind.allCases)
    func defaultTranslationIsListedFirst(kind: RepositoryKind) async throws {
        let passage = try await kind.make().passage(id: "p4")
        #expect(passage.texts.map(\.translation.id) == ["t1", "t2"])
        #expect(passage.texts[1].translation.year == 1900)
        #expect(passage.text(preferring: "t2")?.text == "[t2-4]")
        #expect(passage.text(preferring: "missing")?.text == "[t1-4]")
    }

    @Test(arguments: RepositoryKind.allCases)
    func adjacencyCrossesSectionAndBookBoundaries(kind: RepositoryKind) async throws {
        let repo = try await kind.make()
        #expect(try await repo.adjacentPassageID(to: "p1", direction: .previous) == nil)
        #expect(try await repo.adjacentPassageID(to: "p1", direction: .next) == "p2")
        #expect(try await repo.adjacentPassageID(to: "p2", direction: .next) == "p3")   // next section
        #expect(try await repo.adjacentPassageID(to: "p3", direction: .next) == "p4")   // next book
        #expect(try await repo.adjacentPassageID(to: "p4", direction: .next) == nil)    // stays in collection
        #expect(try await repo.adjacentPassageID(to: "p4", direction: .previous) == "p3")
    }

    @Test(arguments: RepositoryKind.allCases)
    func unknownIDsThrowContentNotFound(kind: RepositoryKind) async throws {
        let repo = try await kind.make()
        await #expect(throws: AppError.contentNotFound("passage nope")) { try await repo.passage(id: "nope") }
        await #expect(throws: AppError.contentNotFound("collection nope")) { try await repo.collection(id: "nope") }
        await #expect(throws: AppError.contentNotFound("section nope")) { try await repo.section(id: "nope") }
        await #expect(throws: AppError.contentNotFound("passage nope")) {
            try await repo.adjacentPassageID(to: "nope", direction: .next)
        }
        #expect(try await repo.passages(sectionID: "nope").isEmpty)
    }

    @Test(arguments: RepositoryKind.allCases)
    func dailyPassageAlternatesTraditionsAndIsStableWithinADay(kind: RepositoryKind) async throws {
        let repo = try await kind.make()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try #require(try await repo.dailyPassage(on: day))
        let sameDay = try await repo.dailyPassage(on: day.addingTimeInterval(60))
        let nextDay = try #require(try await repo.dailyPassage(on: day.addingTimeInterval(86_400)))
        #expect(first == sameDay)
        #expect(first.religionID != nextDay.religionID)
    }

    @Test func bothImplementationsPickTheSameDailyPassage() async throws {
        let memory = try await RepositoryKind.inMemory.make()
        let sqlite = try await RepositoryKind.sqlite.make()
        for day in 0..<8 {
            let date = Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400)
            #expect(try await memory.dailyPassage(on: date)?.id == sqlite.dailyPassage(on: date)?.id)
        }
    }
}

@Suite struct BatchPassageContractTests {
    @Test(arguments: RepositoryKind.allCases)
    func batchFetchKeepsRequestedOrderAndSkipsUnknownIDs(kind: RepositoryKind) async throws {
        let repo = try await kind.make()
        let passages = try await repo.passages(ids: ["p4", "missing", "p1", "p5", "p1"])
        #expect(passages.map(\.id) == ["p4", "p1", "p5", "p1"])
        #expect(passages[0] == (try await repo.passage(id: "p4")))
        #expect(try await repo.passages(ids: []).isEmpty)
    }
}

/// Theme and related-passage contract, run against both implementations.
@Suite struct RelatedPassageContractTests {
    @Test(arguments: RepositoryKind.allCases)
    func themesFollowPackageOrder(kind: RepositoryKind) async throws {
        let repo = try await kind.make()
        #expect(try await repo.themes(passageID: "p5").map(\.id) == ["th2", "th1"])
        #expect(try await repo.themes(passageID: "p3").map(\.name) == ["Theme One", "Theme Two"])
        #expect(try await repo.themes(passageID: "p2").isEmpty)
    }

    @Test(arguments: RepositoryKind.allCases)
    func relatedComesOnlyFromOtherReligionsOrderedBySharedThemes(kind: RepositoryKind) async throws {
        let repo = try await kind.make()
        // p5 (r2) shares two themes with p3, one with p1 and p4 (reading order p1 before p4).
        let related = try await repo.relatedPassages(to: "p5", limit: 10)
        #expect(related.map(\.passage.id) == ["p3", "p1", "p4"])
        #expect(related.allSatisfy { $0.religion.id == "r1" })
        #expect(related[0].sharedThemes.map(\.id) == ["th2", "th1"]) // in the source passage's order
        #expect(related[2].sharedThemes.map(\.id) == ["th2"])
        #expect(try await repo.relatedPassages(to: "p5", limit: 1).map(\.passage.id) == ["p3"])
    }

    @Test(arguments: RepositoryKind.allCases)
    func sameReligionPassagesAreNeverRelated(kind: RepositoryKind) async throws {
        let repo = try await kind.make()
        // p1 and p3 share th1 but are both r1; only p5 (r2) qualifies.
        #expect(try await repo.relatedPassages(to: "p1", limit: 10).map(\.passage.id) == ["p5"])
    }

    @Test(arguments: RepositoryKind.allCases)
    func untaggedPassageHasNoRelatedAndUnknownPassageThrows(kind: RepositoryKind) async throws {
        let repo = try await kind.make()
        #expect(try await repo.relatedPassages(to: "p2", limit: 10).isEmpty)
        #expect(try await repo.relatedPassages(to: "p5", limit: 0).isEmpty)
        await #expect(throws: AppError.contentNotFound("passage nope")) { try await repo.relatedPassages(to: "nope", limit: 5) }
        await #expect(throws: AppError.contentNotFound("passage nope")) { try await repo.themes(passageID: "nope") }
    }
}

@Suite struct DailyRotationTests {
    @Test func skipsEmptyPoolsAndCyclesWithinPools() {
        #expect(DailyRotation.pick(day: 0, poolSizes: []) == nil)
        #expect(DailyRotation.pick(day: 3, poolSizes: [0, 0]) == nil)
        let sizes = [2, 0, 3]
        let picks = (0..<6).compactMap { DailyRotation.pick(day: $0, poolSizes: sizes) }.map { [$0.pool, $0.offset] }
        #expect(picks == [[0, 0], [2, 0], [0, 1], [2, 1], [0, 0], [2, 2]])
    }
}

@Suite struct SampleLibraryValidationTests {
    private func expectCorrupt(_ mutate: (inout [String: Any]) -> Void) throws {
        let dto = try Fixtures.libraryDTO(mutate)
        #expect(throws: AppError.self) { try SampleLibraryRepository(library: dto) }
    }

    private func setPassages(_ json: inout [String: Any], _ transform: ([[String: Any]]) -> [[String: Any]]) {
        json["passages"] = transform(json["passages"] as? [[String: Any]] ?? [])
    }

    @Test func rejectsPassageWithUnknownSection() throws {
        try expectCorrupt { json in
            setPassages(&json) { $0 + [["id": "px", "sectionID": "nope", "sequence": 9, "reference": "X", "originalText": NSNull(), "texts": ["t1": "x"]]] }
        }
    }

    @Test func rejectsTranslationFromAnotherCollection() throws {
        try expectCorrupt { json in
            setPassages(&json) { $0 + [["id": "px", "sectionID": "s1a", "sequence": 9, "reference": "X", "originalText": NSNull(), "texts": ["t3": "x"]]] }
        }
    }

    @Test func rejectsPassageWithoutText() throws {
        try expectCorrupt { json in
            setPassages(&json) { $0 + [["id": "px", "sectionID": "s1a", "sequence": 9, "reference": "X", "originalText": NSNull(), "texts": [String: String]()]] }
        }
    }

    @Test func rejectsDuplicatePassageIDs() throws {
        try expectCorrupt { json in setPassages(&json) { $0 + [$0[0]] } }
    }

    @Test func rejectsMissingDefaultTranslation() throws {
        try expectCorrupt { json in
            var collections = json["collections"] as? [[String: Any]] ?? []
            collections[0]["defaultTranslationID"] = "nope"
            json["collections"] = collections
        }
    }

    @Test func rejectsUnknownTheme() throws {
        try expectCorrupt { json in
            setPassages(&json) { passages in
                var copy = passages
                copy[0]["themes"] = ["no-such-theme"]
                return copy
            }
        }
    }

    @Test func acceptsSchemaTwoPackageWithoutThemes() async throws {
        let dto = try Fixtures.libraryDTO { json in
            json["schemaVersion"] = 2
            json["themes"] = nil
            var passages = json["passages"] as? [[String: Any]] ?? []
            for index in passages.indices { passages[index]["themes"] = nil }
            json["passages"] = passages
        }
        let repo = try SampleLibraryRepository(library: dto)
        #expect(try await repo.themes(passageID: "p5").isEmpty)
    }

    @Test func rejectsUnsupportedSchema() {
        let json = #"{"schemaVersion":99,"religions":[],"sources":[],"collections":[],"translations":[],"books":[],"sections":[],"passages":[]}"#
        #expect(throws: AppError.self) { try SampleLibraryDTO.decode(from: Data(json.utf8)) }
    }

    @Test func rejectsMalformedJSON() {
        #expect(throws: AppError.self) { try SampleLibraryDTO.decode(from: Data("{".utf8)) }
    }
}
