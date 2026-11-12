import Foundation

protocol LoadCollectionContentsUseCaseProtocol: Sendable {
    func execute(collectionID: String) async throws(AppError) -> CollectionContents
}

struct LoadCollectionContentsUseCase: LoadCollectionContentsUseCaseProtocol {
    let repository: any ScriptureRepository

    func execute(collectionID: String) async throws(AppError) -> CollectionContents {
        let collection = try await repository.collection(id: collectionID)
        let translations = try await repository.translations(collectionID: collectionID)
        var entries: [CollectionContents.BookEntry] = []
        for book in try await repository.books(collectionID: collectionID) {
            let sections = try await repository.sections(bookID: book.id)
            entries.append(.init(book: book, sections: sections))
        }
        return CollectionContents(collection: collection, translations: translations, books: entries)
    }
}
