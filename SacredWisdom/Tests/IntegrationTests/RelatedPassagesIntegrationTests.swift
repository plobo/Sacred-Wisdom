import Foundation
import Testing
@testable import SacredWisdom

/// Editorial themes in the real bundled library. Each tag's textual evidence is enforced by the build script;
/// these tests check the links the app derives from them.
@Suite struct RelatedPassagesIntegrationTests {
    private func repository() async throws -> SQLiteScriptureRepository {
        let url = try #require(Bundle(for: AppDependencies.self)
            .url(forResource: SampleLibraryRepository.resourceName, withExtension: "json"))
        return SQLiteScriptureRepository(database: DatabaseManager(
            location: .inMemory,
            bundledPackages: [.init(id: SampleLibraryRepository.resourceName, url: url)]
        ))
    }

    private func allPassageIDs(_ repo: SQLiteScriptureRepository) async throws -> [String] {
        var ids: [String] = []
        for collection in try await repo.fetchCollections() {
            for book in try await repo.books(collectionID: collection.id) {
                for section in try await repo.sections(bookID: book.id) {
                    ids += try await repo.passages(sectionID: section.id).map(\.id)
                }
            }
        }
        return ids
    }

    @Test func mercyLinksMatthewToTheQuranAndPsalms() async throws {
        let related = try await repository().relatedPassages(to: "bible.matthew.5.7", limit: 10)
        #expect(related.map(\.passage.reference) == ["Al-Fatihah 1:1", "Al-Fatihah 1:3", "Psalms 23:6"])
        #expect(related.allSatisfy { $0.sharedThemes.map(\.name) == ["Mercy"] })
    }

    @Test func peacemakersLinkToTheDhammapadaOnHatred() async throws {
        let related = try await repository().relatedPassages(to: "bible.matthew.5.9", limit: 10)
        #expect(related.map(\.passage.id) == ["dhammapada.3", "dhammapada.4", "dhammapada.5", "dhammapada.6"])
    }

    @Test func linksAlwaysCrossTraditionsAndAreSymmetric() async throws {
        let repo = try await repository()
        var linkCount = 0
        for id in try await allPassageIDs(repo) {
            let source = try await repo.passage(id: id)
            for item in try await repo.relatedPassages(to: id, limit: 50) {
                linkCount += 1
                #expect(item.passage.religionID != source.religionID, "\(id) → \(item.passage.id)")
                #expect(!item.sharedThemes.isEmpty)
                let back = try await repo.relatedPassages(to: item.passage.id, limit: 50).map(\.passage.id)
                #expect(back.contains(id), "\(item.passage.id) does not link back to \(id)")
            }
        }
        #expect(linkCount > 0)
    }

    @Test func everyThemeSpansAtLeastTwoTraditions() async throws {
        let repo = try await repository()
        var religionsByTheme: [String: Set<String>] = [:]
        for id in try await allPassageIDs(repo) {
            let passage = try await repo.passage(id: id)
            for theme in try await repo.themes(passageID: id) {
                religionsByTheme[theme.name, default: []].insert(passage.religionID)
            }
        }
        #expect(religionsByTheme.count == 9)
        for (theme, religions) in religionsByTheme {
            #expect(religions.count >= 2, "\(theme) only appears in \(religions)")
        }
    }

    @Test func detailForPsalm23IsCompleteAndRelatedOpenTheirOwnDetails() async throws {
        let repo = try await repository()
        let useCase = LoadPassageDetailUseCase(scripture: repo, related: repo)
        let detail = try await useCase.execute(passageID: "tanakh.psalms.23.3")
        #expect(detail.passage.reference == "Psalms 23:3")
        #expect(detail.passage.originalText?.isEmpty == false)
        #expect(detail.positionInSection == 3)
        #expect(detail.sectionPassageCount == 6)
        #expect(detail.themes.map(\.name) == ["The Divine Name", "Guidance on the Path"])
        #expect(!detail.related.isEmpty)
        for item in detail.related {
            let relatedDetail = try await useCase.execute(passageID: item.passage.id)
            #expect(relatedDetail.passage.id == item.passage.id)
            #expect(relatedDetail.passage.reference == item.passage.reference)
        }
    }
}
