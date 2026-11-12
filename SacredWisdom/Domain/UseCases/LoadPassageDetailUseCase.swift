import Foundation

protocol LoadPassageDetailUseCaseProtocol: Sendable {
    func execute(passageID: String) async throws(AppError) -> PassageDetail
}

struct LoadPassageDetailUseCase: LoadPassageDetailUseCaseProtocol {
    static let relatedLimit = 8

    let scripture: any ScriptureRepository & ReligionRepository
    let related: any RelatedPassageRepository

    func execute(passageID: String) async throws(AppError) -> PassageDetail {
        let passage = try await scripture.passage(id: passageID)
        let section = try await scripture.section(id: passage.sectionID)
        let book = try await scripture.book(id: passage.bookID)
        let collection = try await scripture.collection(id: passage.collectionID)
        guard let religion = try await scripture.fetchReligions().first(where: { $0.id == passage.religionID }) else {
            throw .contentCorrupted("religion \(passage.religionID)")
        }
        let siblings = try await scripture.passages(sectionID: section.id)
        let position = (siblings.firstIndex { $0.id == passage.id } ?? 0) + 1
        return PassageDetail(
            religion: religion, collection: collection, book: book, section: section, passage: passage,
            positionInSection: position, sectionPassageCount: max(siblings.count, position),
            themes: try await related.themes(passageID: passage.id),
            related: try await related.relatedPassages(to: passage.id, limit: Self.relatedLimit)
        )
    }
}
