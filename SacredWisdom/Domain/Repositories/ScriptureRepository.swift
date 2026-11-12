import Foundation

/// Read access to scripture structure and passages. Ordering is always by `sequence`.
protocol ScriptureRepository: Sendable {
    func collection(id: String) async throws(AppError) -> ScriptureCollection
    func translations(collectionID: String) async throws(AppError) -> [Translation]
    func books(collectionID: String) async throws(AppError) -> [ScriptureBook]
    func book(id: String) async throws(AppError) -> ScriptureBook
    func sections(bookID: String) async throws(AppError) -> [ScriptureSection]
    func section(id: String) async throws(AppError) -> ScriptureSection
    func passages(sectionID: String) async throws(AppError) -> [ScripturePassage]
    func passage(id: String) async throws(AppError) -> ScripturePassage
    /// Several passages in one call, in the order requested; unknown IDs are skipped.
    func passages(ids: [String]) async throws(AppError) -> [ScripturePassage]
    /// The neighbouring passage in reading order across the whole collection, or nil at either end.
    func adjacentPassageID(to passageID: String, direction: PassageDirection) async throws(AppError) -> String?
}

extension ScriptureRepository {
    func passages(ids: [String]) async throws(AppError) -> [ScripturePassage] {
        var result: [ScripturePassage] = []
        for id in ids {
            do throws(AppError) {
                result.append(try await passage(id: id))
            } catch .contentNotFound {
                continue
            }
        }
        return result
    }
}

/// Remembers the reader's chosen translation per collection.
protocol TranslationPreferenceStore: Sendable {
    func preferredTranslationID(collectionID: String) async -> String?
    func setPreferredTranslationID(_ translationID: String, collectionID: String) async
}
