import Foundation
import Observation

@Observable
@MainActor
final class CollectionBrowserViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(CollectionContents)
        case failed(String)
    }

    private(set) var state: State = .idle
    let collectionID: String
    private let loadContents: any LoadCollectionContentsUseCaseProtocol

    init(collectionID: String, loadContents: any LoadCollectionContentsUseCaseProtocol) {
        self.collectionID = collectionID
        self.loadContents = loadContents
    }

    func load() async {
        if case .loading = state { return }
        state = .loading
        do {
            state = .loaded(try await loadContents.execute(collectionID: collectionID))
        } catch {
            state = .failed(error.userMessage)
        }
    }

    /// e.g. "Sanskrit · 1 translation"
    var languageSummary: String? {
        guard case .loaded(let contents) = state else { return nil }
        let language = LanguageInfo.displayName(contents.collection.originalLanguage)
        let count = contents.translations.count
        let translations = count == 1
            ? String(localized: "1 translation")
            : String(localized: "\(count) translations")
        return "\(language) · \(translations)"
    }
}
