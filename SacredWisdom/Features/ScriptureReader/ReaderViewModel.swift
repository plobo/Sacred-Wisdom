import Foundation
import Observation

@Observable
@MainActor
final class ReaderViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(ReaderPage)
        case failed(String)
    }

    static let fontScaleRange: ClosedRange<Double> = 0.8...1.8
    static let fontScaleStep = 0.1

    private(set) var state: State = .idle
    private(set) var selectedTranslationID: String?
    private(set) var fontScale: Double = 1.0
    private(set) var isNavigating = false
    let bookmarks: PassageBookmarkController
    /// Listening; nil when the screen is built without audio (some tests).
    let audio: AudioPlaybackController?

    private var start: ReaderStart
    /// Translation requested by the caller (e.g. a search match); wins over the stored preference once.
    private let initialTranslationID: String?
    private let loadPage: any LoadReaderPageUseCaseProtocol
    private let preferences: any TranslationPreferenceStore
    private let userData: UserDataContext
    private let display: AppPreferences?
    private let resolveAudio: any ResolveAudioTrackUseCaseProtocol
    /// Set when a passage finished playing and the reader moved on, so the next passage starts by itself.
    private var continuesListening = false

    init(
        start: ReaderStart,
        initialTranslationID: String? = nil,
        loadPage: any LoadReaderPageUseCaseProtocol,
        preferences: any TranslationPreferenceStore,
        userData: UserDataContext = .unavailable(),
        display: AppPreferences? = nil,
        audio: AudioPlaybackController? = nil,
        resolveAudio: any ResolveAudioTrackUseCaseProtocol = ResolveAudioTrackUseCase()
    ) {
        self.audio = audio
        self.resolveAudio = resolveAudio
        self.display = display
        fontScale = display?.readerTextScale ?? 1
        self.start = start
        self.initialTranslationID = initialTranslationID
        self.loadPage = loadPage
        self.preferences = preferences
        self.userData = userData
        self.bookmarks = PassageBookmarkController(userData: userData)
        audio?.onFinished = { [weak self] in self?.passageFinishedPlaying() }
    }

    // MARK: Loading and navigation

    func load() async {
        if case .loading = state { return }
        state = .loading
        await show(start)
    }

    func goToNext() async {
        guard let id = page?.nextPassageID else { return }
        await navigate(to: id)
    }

    func goToPrevious() async {
        guard let id = page?.previousPassageID else { return }
        await navigate(to: id)
    }

    private func navigate(to passageID: String) async {
        guard !isNavigating else { return }
        isNavigating = true
        defer { isNavigating = false }
        await show(.passage(passageID))
    }

    private func show(_ target: ReaderStart) async {
        do {
            let page = try await loadPage.execute(target)
            start = .passage(page.passage.id)
            if selectedTranslationID == nil || !page.translations.contains(where: { $0.id == selectedTranslationID }) {
                if let requested = initialTranslationID, page.translations.contains(where: { $0.id == requested }) {
                    selectedTranslationID = requested
                } else {
                    selectedTranslationID = await preferences.preferredTranslationID(collectionID: page.collection.id)
                        ?? page.collection.defaultTranslationID
                }
            }
            state = .loaded(page)
            await prepareAudio()
            await bookmarks.show(passageID: page.passage.id)
            await userData.recordView(of: page.passage.id)
        } catch {
            state = .failed(error.userMessage)
        }
    }

    // MARK: Translation

    func selectTranslation(_ translationID: String) async {
        guard let page, page.translations.contains(where: { $0.id == translationID }) else { return }
        selectedTranslationID = translationID
        await preferences.setPreferredTranslationID(translationID, collectionID: page.collection.id)
        await prepareAudio()
    }

    // MARK: Listening

    /// Loads the shown passage's audio. Keeps listening across passages: if audio was playing (or a passage just
    /// finished and continuous playback moved on), the new passage starts playing.
    private func prepareAudio() async {
        guard let audio, let page else { return }
        let autoplay = audio.isPlaying || continuesListening
        continuesListening = false
        let availability = await resolveAudio.execute(passage: page.passage, translationID: selectedTranslationID)
        guard self.page?.passage.id == page.passage.id else { return }
        audio.load(availability, autoplay: autoplay)
    }

    private func passageFinishedPlaying() {
        guard display?.continuousPlayback ?? true, page?.nextPassageID != nil else { return }
        continuesListening = true
        Task { await goToNext() }
    }

    /// Leaving the reader stops listening, so audio never plays with no controls on screen.
    func stopListening() {
        continuesListening = false
        audio?.stop()
    }

    // MARK: Font size

    /// Changes are remembered as the default size (Settings → Scripture Text Size).
    func increaseFontSize() {
        fontScale = min(Self.fontScaleRange.upperBound, (fontScale + Self.fontScaleStep).rounded(toPlaces: 1))
        display?.readerTextScale = fontScale
    }

    func decreaseFontSize() {
        fontScale = max(Self.fontScaleRange.lowerBound, (fontScale - Self.fontScaleStep).rounded(toPlaces: 1))
        display?.readerTextScale = fontScale
    }

    var canIncreaseFontSize: Bool { fontScale < Self.fontScaleRange.upperBound }
    var canDecreaseFontSize: Bool { fontScale > Self.fontScaleRange.lowerBound }

    // MARK: Derived display state

    var page: ReaderPage? {
        guard case .loaded(let page) = state else { return nil }
        return page
    }

    var displayedText: PassageText? {
        page?.passage.text(preferring: selectedTranslationID)
    }

    var hasTranslationChoice: Bool { (page?.translations.count ?? 0) > 1 }
    var canGoPrevious: Bool { page?.previousPassageID != nil && !isNavigating }
    var canGoNext: Bool { page?.nextPassageID != nil && !isNavigating }

    var isOriginalRightToLeft: Bool {
        page.map { LanguageInfo.isRightToLeft($0.passage.originalLanguage) } ?? false
    }

    var originalLanguageName: String {
        page.map { LanguageInfo.displayName($0.passage.originalLanguage) } ?? ""
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
