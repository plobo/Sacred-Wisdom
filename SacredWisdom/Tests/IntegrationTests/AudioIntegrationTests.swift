import Foundation
import Testing
@testable import SacredWisdom

/// Listening over the real bundled library: which texts may be read aloud, and that what is read is the
/// verified text itself.
@Suite struct AudioIntegrationTests {
    private func repository() async throws -> SQLiteScriptureRepository {
        let url = try #require(Bundle(for: AppDependencies.self)
            .url(forResource: SampleLibraryRepository.resourceName, withExtension: "json"))
        return SQLiteScriptureRepository(database: DatabaseManager(
            location: .inMemory,
            bundledPackages: [.init(id: SampleLibraryRepository.resourceName, url: url)]
        ))
    }

    @Test(arguments: ["bhagavad-gita", "bible", "quran", "tanakh", "tripitaka", "guru-granth-sahib"])
    func everyBundledTranslationCanBeHeardVerbatim(collectionID: String) async throws {
        let repo = try await repository()
        let contents = try await LoadCollectionContentsUseCase(repository: repo).execute(collectionID: collectionID)
        let section = try #require(contents.books.first?.sections.first)
        let page = try await LoadReaderPageUseCase(repository: repo).execute(.section(section.id))
        for text in page.passage.texts {
            let result = await ResolveAudioTrackUseCase().execute(passage: page.passage, translationID: text.translation.id)
            guard case .available(let track) = result, case .speech(let spoken, let code) = track.content else {
                Issue.record("\(text.translation.id) should be speakable: \(text.translation.source.license)")
                continue
            }
            #expect(spoken == text.text.trimmingCharacters(in: .whitespacesAndNewlines))
            #expect(code == text.translation.languageCode)
            if let original = page.passage.originalText { #expect(spoken != original) }
        }
    }

    @Test func originalOnlySourcesAreNotLicensedForSpeech() async throws {
        let repo = try await repository()
        let quran = try await LoadCollectionContentsUseCase(repository: repo).execute(collectionID: "quran")
        let sectionID = try #require(quran.books.first?.sections.first?.id)
        let page = try await LoadReaderPageUseCase(repository: repo).execute(.section(sectionID))
        let tanzil = try #require(page.passage.originalSource)
        #expect(!AudioLicensePolicy.allowsSynthesizedSpeech(tanzil))
    }
}
