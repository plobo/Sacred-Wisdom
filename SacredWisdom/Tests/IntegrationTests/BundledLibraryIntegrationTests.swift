import Foundation
import Testing
@testable import SacredWisdom

/// Verifies the real bundled sample library. Expected references are the verified test data
/// (see tools/content/build_sample_library.py for provenance of each passage).
@Suite struct BundledLibraryIntegrationTests {
    private static let expectedReferences: [String: [String]] = [
        "bhagavad-gita": (47...50).map { "Bhagavad Gita 2.\($0)" },
        "bible": (3...10).map { "Matthew 5:\($0)" },
        "quran": (1...7).map { "Al-Fatihah 1:\($0)" },
        "tanakh": (1...6).map { "Psalms 23:\($0)" },
        "tripitaka": (1...6).map { "Dhammapada \($0)" },
        "guru-granth-sahib": [
            "Ang 1 · Mool Mantar", "Ang 1 · Japji Sahib, Salok",
            "Ang 1 · Japji Sahib, Pauri 1", "Ang 1 · Japji Sahib, Pauri 2",
        ],
    ]

    /// The bundled package imported into a fresh SQLite database, exactly as the app does at launch.
    private func repository() async throws -> SQLiteScriptureRepository {
        let url = try #require(Bundle(for: AppDependencies.self)
            .url(forResource: SampleLibraryRepository.resourceName, withExtension: "json"))
        return SQLiteScriptureRepository(database: DatabaseManager(
            location: .inMemory,
            bundledPackages: [.init(id: SampleLibraryRepository.resourceName, url: url)]
        ))
    }

    @Test func allSixTraditionsHaveACollection() async throws {
        let summaries = try await LoadReligionSummariesUseCase(religionRepository: await repository()).execute()
        #expect(summaries.map(\.id) == ["hinduism", "christianity", "islam", "judaism", "buddhism", "sikhism"])
        #expect(summaries.allSatisfy { $0.collection != nil })
    }

    @Test(arguments: expectedReferences.keys.sorted())
    func collectionIsBrowsableAndReferencesMatch(collectionID: String) async throws {
        let repo = try await repository()
        let contents = try await LoadCollectionContentsUseCase(repository: repo).execute(collectionID: collectionID)
        var references: [String] = []
        for entry in contents.books {
            for section in entry.sections {
                for passage in try await repo.passages(sectionID: section.id) {
                    references.append(passage.reference)
                    #expect(passage.texts.allSatisfy { !$0.text.isEmpty }, "\(passage.id) has empty text")
                    #expect(passage.texts.first?.translation.id == contents.collection.defaultTranslationID)
                }
            }
        }
        #expect(references == Self.expectedReferences[collectionID])
    }

    @Test func everyTranslationAndOriginalIsAttributedAndLicensed() async throws {
        let repo = try await repository()
        for collection in try await repo.fetchCollections() {
            for translation in try await repo.translations(collectionID: collection.id) {
                #expect(!translation.source.attribution.isEmpty && !translation.source.license.isEmpty, "\(translation.id)")
            }
            if collection.originalLanguage != "en" {
                #expect(collection.originalSource != nil, "\(collection.id) has no original source")
            }
        }
    }

    @Test func readingAcrossTheWholeBibleSampleIsContinuous() async throws {
        let useCase = LoadReaderPageUseCase(repository: try await repository())
        var page = try await useCase.execute(.section("bible.matthew.5"))
        var visited = [page.passage.reference]
        while let next = page.nextPassageID {
            page = try await useCase.execute(.passage(next))
            visited.append(page.passage.reference)
        }
        #expect(visited == Self.expectedReferences["bible"])
    }

    @Test func stableIDsAreUnchanged() async throws {
        let repo = try await repository()
        let passage = try await repo.passage(id: "bible.matthew.5.9")
        #expect(passage.reference == "Matthew 5:9")
        #expect(passage.texts.map(\.translation.id) == ["bible-kjv", "bible-web"])
    }

    @Test func dailyPassageCoversAllTraditionsWithinSixDays() async throws {
        let repo = try await repository()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var religions = Set<String>()
        for day in 0..<6 {
            let passage = try #require(try await repo.dailyPassage(on: start.addingTimeInterval(Double(day) * 86_400)))
            religions.insert(passage.religionID)
        }
        #expect(religions.count == 6)
    }

    @Test func bundledPackageMatchesTheJSONReferenceImplementation() async throws {
        let sqlite = try await repository()
        let memory = try SampleLibraryRepository.fromBundle(Bundle(for: AppDependencies.self))
        for collection in try await memory.fetchCollections() {
            for book in try await memory.books(collectionID: collection.id) {
                for section in try await memory.sections(bookID: book.id) {
                    #expect(try await sqlite.passages(sectionID: section.id) == memory.passages(sectionID: section.id))
                }
            }
        }
    }

    @Test func fullTextSearchWorksOfflineAcrossTraditions() async throws {
        let index = FullTextSearchIndex(database: try await repository().database)
        func ids(_ terms: [String], phrase: Bool = false) async throws -> Set<String> {
            Set(try await index.search(terms: terms, phrase: phrase).map(\.passageID))
        }
        #expect(try await ids(["peacemakers"]) == ["bible.matthew.5.9"])
        #expect(try await ids(["shepherd"]) == ["tanakh.psalms.23.1"])
        #expect(try await ids(["hatred", "love"]).contains("dhammapada.5"))
        #expect(try await ids(["skill", "in", "action"], phrase: true) == ["gita.2.50"])
        #expect(try await ids(["Nanak"]).isSuperset(of: ["ggs.1.salok", "ggs.1.pauri-1", "ggs.1.pauri-2"]))
        #expect(try await ids(["Beneficent", "Merciful"]) == ["quran.1.1", "quran.1.3"])
        // Diacritic-insensitive matching on romanized Pali: "Manopubbangama" finds "Manopubbaṅgamā".
        #expect(try await ids(["Manopubbangama"]) == ["dhammapada.1", "dhammapada.2"])
        // Original-script search.
        #expect(try await ids(["ਨਾਨਕ"]).contains("ggs.1.salok"))
        #expect(try await ids(["רֹעִי"]) == ["tanakh.psalms.23.1"])
        // Unpointed Hebrew and Arabic find pointed source text (folded index, Phase 4).
        #expect(try await ids(["רעי"]) == ["tanakh.psalms.23.1"])
        #expect(try await ids(["יהוה"]) == ["tanakh.psalms.23.1", "tanakh.psalms.23.6"])
        #expect(try await ids(["الرحيم"]) == ["quran.1.1", "quran.1.3"])
        #expect(try await ids(["الدين"]) == ["quran.1.4"])
    }
}
