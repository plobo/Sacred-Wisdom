import Foundation

/// Used when bundled content fails to load, so the UI shows an error state instead of crashing.
struct UnavailableLibraryRepository: ReligionRepository, ScriptureRepository, PassageRepository, ScriptureSearchRepository,
    RelatedPassageRepository {
    let error: AppError

    func fetchReligions() async throws(AppError) -> [Religion] { throw error }
    func fetchCollections() async throws(AppError) -> [ScriptureCollection] { throw error }
    func collection(id: String) async throws(AppError) -> ScriptureCollection { throw error }
    func translations(collectionID: String) async throws(AppError) -> [Translation] { throw error }
    func books(collectionID: String) async throws(AppError) -> [ScriptureBook] { throw error }
    func book(id: String) async throws(AppError) -> ScriptureBook { throw error }
    func sections(bookID: String) async throws(AppError) -> [ScriptureSection] { throw error }
    func section(id: String) async throws(AppError) -> ScriptureSection { throw error }
    func passages(sectionID: String) async throws(AppError) -> [ScripturePassage] { throw error }
    func passage(id: String) async throws(AppError) -> ScripturePassage { throw error }
    func adjacentPassageID(to passageID: String, direction: PassageDirection) async throws(AppError) -> String? { throw error }
    func dailyPassage(on date: Date) async throws(AppError) -> ScripturePassage? { throw error }
    func themes(passageID: String) async throws(AppError) -> [PassageTheme] { throw error }
    func relatedPassages(to passageID: String, limit: Int) async throws(AppError) -> [RelatedPassage] { throw error }
    func search(query: SearchQuery, filters: SearchFilters) async throws(AppError) -> [ScriptureSearchResult] { throw error }
}
