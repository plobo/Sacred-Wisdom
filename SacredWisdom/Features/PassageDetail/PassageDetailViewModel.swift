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
    /// Listening; nil when the screen is built without audio (some tests).
    let audio: AudioPlaybackController?
    /// The translation being listened to (the primary one until the listener picks another).
    private(set) var audioTranslationID: String?

    let passageID: String
    private let initialTranslationID: String?
    private let loadDetail: any LoadPassageDetailUseCaseProtocol
    private let preferences: any TranslationPreferenceStore
    private let userData: UserDataContext
    private let resolveAudio: any ResolveAudioTrackUseCaseProtocol

    init(
        passageID: String,
        initialTranslationID: String? = nil,
        loadDetail: any LoadPassageDetailUseCaseProtocol,
        preferences: any TranslationPreferenceStore,
        userData: UserDataContext,
        audio: AudioPlaybackController? = nil,
        resolveAudio: any ResolveAudioTrackUseCaseProtocol = ResolveAudioTrackUseCase()
    ) {
        self.audio = audio
        self.resolveAudio = resolveAudio
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
            await selectAudioTranslation(primaryTranslationID)
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

    // MARK: Listening

    /// Picks which translation to hear; playing audio carries on in the new one.
    func selectAudioTranslation(_ translationID: String?) async {
        guard let audio, let passage = detail?.passage else { return }
        let wasPlaying = audio.isPlaying
        audioTranslationID = translationID
        let availability = await resolveAudio.execute(passage: passage, translationID: translationID)
        audio.load(availability, autoplay: wasPlaying)
    }

    var audioTranslationChoices: [AudioPlayerBar.TranslationChoice] {
        orderedTexts.map { .init(id: $0.translation.id, name: $0.translation.name) }
    }

    func stopListening() {
        audio?.stop()
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
