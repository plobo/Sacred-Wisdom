import Foundation

protocol LoadReaderPageUseCaseProtocol: Sendable {
    func execute(_ start: ReaderStart) async throws(AppError) -> ReaderPage
}

struct LoadReaderPageUseCase: LoadReaderPageUseCaseProtocol {
    let repository: any ScriptureRepository

    func execute(_ start: ReaderStart) async throws(AppError) -> ReaderPage {
        let passage = try await resolvePassage(start)
        let section = try await repository.section(id: passage.sectionID)
        let book = try await repository.book(id: passage.bookID)
        let collection = try await repository.collection(id: passage.collectionID)
        let translations = try await repository.translations(collectionID: collection.id)
        let previous = try await repository.adjacentPassageID(to: passage.id, direction: .previous)
        let next = try await repository.adjacentPassageID(to: passage.id, direction: .next)
        return ReaderPage(
            collection: collection, book: book, section: section, passage: passage,
            translations: translations, previousPassageID: previous, nextPassageID: next
        )
    }

    private func resolvePassage(_ start: ReaderStart) async throws(AppError) -> ScripturePassage {
        switch start {
        case .passage(let id):
            return try await repository.passage(id: id)
        case .section(let id):
            guard let first = try await repository.passages(sectionID: id).first else {
                throw .contentNotFound("No passages in section \(id)")
            }
            return first
        }
    }
}
