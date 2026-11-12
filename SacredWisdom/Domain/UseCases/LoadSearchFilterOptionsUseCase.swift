import Foundation

protocol LoadSearchFilterOptionsUseCaseProtocol: Sendable {
    func execute() async throws(AppError) -> SearchFilterOptions
}

struct LoadSearchFilterOptionsUseCase: LoadSearchFilterOptionsUseCaseProtocol {
    let religions: any ReligionRepository
    let scripture: any ScriptureRepository

    func execute() async throws(AppError) -> SearchFilterOptions {
        let traditions = try await religions.fetchReligions().sorted { $0.sortOrder < $1.sortOrder }
        let collections = try await religions.fetchCollections()
        var translations: [Translation] = []
        for collection in collections {
            translations += try await scripture.translations(collectionID: collection.id)
        }
        var languages: [String] = []
        for code in collections.map(\.originalLanguage) + translations.map(\.languageCode) where !languages.contains(code) {
            languages.append(code)
        }
        return SearchFilterOptions(
            religions: traditions,
            collections: collections,
            languageCodes: languages.sorted { LanguageInfo.displayName($0) < LanguageInfo.displayName($1) },
            translations: translations
        )
    }
}
