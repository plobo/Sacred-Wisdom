import Foundation
import Observation

/// Screen 7: one passage with original text, every translation, attribution, context, related passages,
/// bookmark, note and sharing.
@Observable
@MainActor
final class PassageDetailViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(PassageDetail)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var primaryTranslationID: String?
    let bookmarks: PassageBookmarkController

    let passageID: String
    private let initialTranslationID: String?
    private let loadDetail: any LoadPassageDetailUseCaseProtocol
    private let preferences: any TranslationPreferenceStore
    private let userData: UserDataContext

    init(
        passageID: String,
        initialTranslationID: String? = nil,
        loadDetail: any LoadPassageDetailUseCaseProtocol,
        preferences: any TranslationPreferenceStore,
        userData: UserDataContext
    ) {
        self.passageID = passageID
        self.initialTranslationID = initialTranslationID
        self.loadDetail = loadDetail
        self.preferences = preferences
        self.userData = userData
        self.bookmarks = PassageBookmarkController(userData: userData)
    }

    // MARK: Loading

    func load() async {
        if case .loading = state { return }
        state = .loading
        do {
            let detail = try await loadDetail.execute(passageID: passageID)
            primaryTranslationID = await resolvePrimaryTranslation(detail)
            state = .loaded(detail)
            await bookmarks.show(passageID: passageID)
            await userData.recordView(of: passageID)
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func resolvePrimaryTranslation(_ detail: PassageDetail) async -> String? {
        let available = Set(detail.passage.texts.map(\.translation.id))
        if let requested = initialTranslationID, available.contains(requested) { return requested }
        if let preferred = await preferences.preferredTranslationID(collectionID: detail.collection.id),
           available.contains(preferred) { return preferred }
        return detail.passage.texts.first?.translation.id
    }

    // MARK: Display

    var detail: PassageDetail? {
        guard case .loaded(let detail) = state else { return nil }
        return detail
    }

    /// Every translation, with the primary one (matched, preferred or default) first.
    var orderedTexts: [PassageText] {
        guard let texts = detail?.passage.texts else { return [] }
        guard let index = texts.firstIndex(where: { $0.translation.id == primaryTranslationID }) else { return texts }
        var ordered = texts
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }

    var shareText: String? {
        guard let detail else { return nil }
        return PassageShareFormatter.text(for: detail.passage, collectionName: detail.collection.name,
                                          translationID: primaryTranslationID)
    }

    var isOriginalRightToLeft: Bool {
        detail.map { LanguageInfo.isRightToLeft($0.passage.originalLanguage) } ?? false
    }

    var originalLanguageName: String {
        detail.map { LanguageInfo.displayName($0.passage.originalLanguage) } ?? ""
    }
}
