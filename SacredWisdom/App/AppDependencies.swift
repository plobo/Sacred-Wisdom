import Foundation

/// Composition root. Builds repositories and use cases, and vends view models.
/// Tests construct it with their own repositories.
@MainActor
final class AppDependencies {
    typealias LibraryRepository = ReligionRepository & ScriptureRepository & PassageRepository & RelatedPassageRepository

    let configuration: AppConfiguration
    let library: any LibraryRepository
    let searchRepository: any ScriptureSearchRepository
    let searchHistory: any SearchHistoryRepository
    let translationPreferences: any TranslationPreferenceStore
    let userData: UserDataContext
    let preferences: AppPreferences
    /// Present when the scripture database opened; downloads need it.
    let downloads: DownloadManager?

    init(
        configuration: AppConfiguration,
        library: any LibraryRepository,
        searchRepository: any ScriptureSearchRepository,
        searchHistory: any SearchHistoryRepository,
        userData: UserDataContext,
        downloads: DownloadManager? = nil,
        preferences: AppPreferences? = nil,
        translationPreferences: any TranslationPreferenceStore = InMemoryTranslationPreferenceStore()
    ) {
        self.downloads = downloads
        self.preferences = preferences ?? AppPreferences(defaults: Self.volatileDefaults())
        self.configuration = configuration
        self.library = library
        self.searchRepository = searchRepository
        self.searchHistory = searchHistory
        self.userData = userData
        self.translationPreferences = translationPreferences
    }

    static func live(configuration: AppConfiguration = .current()) -> AppDependencies {
        let packagesDirectory = try? configuration.packagesDirectory()
        // UI tests start without downloads unless a test relaunches to check they persisted.
        if configuration.isUITesting, !configuration.keepsDownloadedPackages, let packagesDirectory {
            try? FileManager.default.removeItem(at: packagesDirectory)
        }
        let library: any LibraryRepository
        let search: any ScriptureSearchRepository
        var database: DatabaseManager?
        do {
            let manager = try makeDatabase(configuration: configuration, packagesDirectory: packagesDirectory)
            let sqlite = SQLiteScriptureRepository(database: manager)
            database = manager
            library = sqlite
            search = CombinedSearchRepository(
                primary: LocalKeywordSearchRepository(index: FullTextSearchIndex(database: manager), scripture: sqlite),
                supplementary: []
            )
        } catch {
            Log.database.fault("Scripture library unavailable: \(String(describing: error), privacy: .public)")
            let unavailable = UnavailableLibraryRepository(error: error)
            library = unavailable
            search = unavailable
        }

        if configuration.resetsUserData, case .file(let url) = configuration.userDataLocation {
            PersistenceManager.deleteStore(at: url)
        }
        let history: any SearchHistoryRepository
        let bookmarks: any BookmarkRepository
        let readingHistory: any ReadingHistoryRepository
        do {
            let container = try PersistenceManager.makeContainer(location: configuration.userDataLocation)
            history = SwiftDataSearchHistoryRepository(modelContainer: container)
            bookmarks = SwiftDataBookmarkRepository(modelContainer: container)
            readingHistory = SwiftDataReadingHistoryRepository(modelContainer: container)
        } catch {
            Log.userData.fault("User data store unavailable: \(String(describing: error), privacy: .public)")
            history = UnavailableSearchHistoryRepository()
            bookmarks = UnavailableUserDataRepository()
            readingHistory = UnavailableUserDataRepository()
        }

        let changes = UserDataChanges()
        var downloads: DownloadManager?
        if let database, let packagesDirectory {
            downloads = DownloadManager(
                manifestURL: configuration.contentManifestURL,
                transport: URLSessionPackageTransport(),
                installer: PackageInstaller(store: PackageFileStore(directory: packagesDirectory), database: database),
                changes: changes
            )
        }

        // UI tests get fresh settings every launch; the app uses the standard defaults.
        let defaults = configuration.isUITesting ? volatileDefaults() : .standard
        return AppDependencies(
            configuration: configuration,
            library: library,
            searchRepository: search,
            searchHistory: history,
            userData: UserDataContext(bookmarks: bookmarks, history: readingHistory, changes: changes),
            downloads: downloads,
            preferences: AppPreferences(defaults: defaults),
            translationPreferences: configuration.isUITesting
                ? InMemoryTranslationPreferenceStore()
                : UserDefaultsTranslationPreferenceStore(defaults: defaults)
        )
    }

    /// An emptied, process-private defaults domain.
    static func volatileDefaults() -> UserDefaults {
        let name = "com.sacredwisdom.volatile"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// UI tests get a fresh in-memory database so every run starts from the same state (downloaded package
    /// files, which live in their own folder, are re-imported at launch).
    private static func makeDatabase(configuration: AppConfiguration, packagesDirectory: URL?) throws(AppError) -> DatabaseManager {
        guard let package = Bundle.main.url(forResource: SampleLibraryRepository.resourceName, withExtension: "json") else {
            throw .contentNotFound("\(SampleLibraryRepository.resourceName).json")
        }
        let location: SQLiteConnection.Location = configuration.isUITesting
            ? .inMemory
            : .file(try DatabaseManager.defaultFileURL())
        return DatabaseManager(
            location: location,
            bundledPackages: [.init(id: SampleLibraryRepository.resourceName, url: package)],
            downloadedPackagesDirectory: packagesDirectory
        )
    }

    private var loadSummaries: any LoadReligionSummariesUseCaseProtocol {
        LoadReligionSummariesUseCase(religionRepository: library)
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            loadDashboard: LoadHomeDashboardUseCase(
                loadSummaries: loadSummaries,
                passageRepository: library,
                recentPassages: LoadRecentPassagesUseCase(history: userData.history, scripture: library)
            ),
            changes: userData.changes
        )
    }

    func makeLibraryViewModel() -> LibraryViewModel {
        LibraryViewModel(loadSummaries: loadSummaries, changes: userData.changes)
    }

    func makeCollectionBrowserViewModel(collectionID: String) -> CollectionBrowserViewModel {
        CollectionBrowserViewModel(
            collectionID: collectionID,
            loadContents: LoadCollectionContentsUseCase(repository: library)
        )
    }

    func makeReaderViewModel(start: ReaderStart, translationID: String? = nil) -> ReaderViewModel {
        ReaderViewModel(
            start: start,
            initialTranslationID: translationID,
            loadPage: LoadReaderPageUseCase(repository: library),
            preferences: translationPreferences,
            userData: userData,
            display: preferences,
            audio: makeAudioController()
        )
    }

    func makePassageDetailViewModel(passageID: String, translationID: String? = nil) -> PassageDetailViewModel {
        PassageDetailViewModel(
            passageID: passageID,
            initialTranslationID: translationID,
            loadDetail: LoadPassageDetailUseCase(scripture: library, related: library),
            preferences: translationPreferences,
            userData: userData,
            audio: makeAudioController()
        )
    }

    func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(
            search: SearchScriptureUseCase(search: searchRepository, religions: library),
            history: searchHistory,
            loadOptions: LoadSearchFilterOptionsUseCase(religions: library, scripture: library),
            userData: userData
        )
    }

    func makeFavoritesViewModel() -> FavoritesViewModel {
        FavoritesViewModel(loadFavorites: LoadFavoritesUseCase(bookmarks: userData.bookmarks, scripture: library),
                           userData: userData)
    }

    /// One audio service for the app, so only one passage plays at a time. Under UI testing it is scripted
    /// (silent, plays each passage in about two seconds; `-ui-testing-audio-no-voice` has no voices).
    private(set) lazy var audioService: any AudioService = {
        if configuration.isUITesting {
            return ScriptedAudioService(voicedLanguages: configuration.audioHasNoVoices ? [] : ["en"],
                                        duration: .seconds(2))
        }
        let session = AudioSessionController()
        return RoutingAudioService(speech: SystemSpeechAudioService(session: session),
                                   recordings: RecordedAudioService(session: session))
    }()

    func makeAudioController() -> AudioPlaybackController {
        AudioPlaybackController(service: audioService, preferences: preferences)
    }

    func makeVoiceSearchViewModel() -> VoiceSearchViewModel {
        VoiceSearchViewModel(service: speechRecognition)
    }

    /// Live recognizer, or a scripted one under UI testing (automation has no microphone).
    private lazy var speechRecognition: any SpeechRecognitionService = {
        if let scripted = configuration.scriptedSpeech {
            return ScriptedSpeechRecognitionService(transcript: scripted.transcript, availability: scripted.availability)
        }
        return AppleSpeechRecognitionService()
    }()

    /// On-device Foundation Models in the app. Under UI testing: unavailable, or a scripted reply whose second
    /// sentence quotes words that are in no passage (so tests can see the validator remove it).
    private(set) lazy var aiService: any ScriptureAIService = {
        guard configuration.isUITesting else { return FoundationModelsScriptureAIService(religions: library) }
        guard configuration.usesScriptedAI else {
            return UnavailableScriptureAIService(reason: String(localized: "AI is not available in this test run."))
        }
        return ScriptedScriptureAIService(
            explanation: "These passages speak to the question in their own words [1]. One passage says “love conquers all things” [1].",
            citedPassageNumbers: [1]
        )
    }()

    private(set) lazy var aiPreferences: any AIPreferenceStore = configuration.isUITesting
        ? InMemoryAIPreferenceStore()
        : UserDefaultsAIPreferenceStore(defaults: .standard)

    func makeAskQuestionViewModel() -> AskQuestionViewModel {
        AskQuestionViewModel(answerQuestion: AnswerQuestionUseCase(
            search: SearchScriptureUseCase(search: searchRepository, religions: library),
            ai: aiService,
            preferences: aiPreferences
        ))
    }

    func makeIntentService() -> ScriptureIntentService {
        ScriptureIntentService(search: SearchScriptureUseCase(search: searchRepository, religions: library), scripture: library)
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(userData: userData, aiPreferences: aiPreferences, ai: aiService, display: preferences,
                          scripture: library, translationPreferences: translationPreferences)
    }
}
