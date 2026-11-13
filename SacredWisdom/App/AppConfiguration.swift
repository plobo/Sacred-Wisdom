import Foundation

/// Runtime configuration resolved once at launch.
struct AppConfiguration: Sendable {
    static let uiTestingArgument = "-ui-testing"
    /// UI tests only: keep user data in a named file store (so a test can relaunch and check persistence).
    static let userDataStoreArgument = "-ui-testing-user-data-store"
    /// UI tests only: delete that store before launching.
    static let resetUserDataArgument = "-ui-testing-reset-user-data"

    let appVersion: String
    let isUITesting: Bool
    let splashDuration: Duration
    let userDataLocation: PersistenceManager.Location
    let resetsUserData: Bool
    /// Where the content manifest lives. Production: the `SWContentManifestURL` Info.plist value (from the
    /// `CONTENT_MANIFEST_URL` build setting; https only). Unset means downloads are not configured.
    let contentManifestURL: URL?
    /// UI tests only: `-ui-testing-manifest-url <url>` (typically a file:// URL to content/packages/manifest.json).
    static let manifestURLArgument = "-ui-testing-manifest-url"
    static let manifestInfoKey = "SWContentManifestURL"
    /// UI tests only: keep downloaded packages from the previous launch (otherwise they are cleared).
    static let keepPackagesArgument = "-ui-testing-keep-packages"
    var keepsDownloadedPackages: Bool { ProcessInfo.processInfo.arguments.contains(Self.keepPackagesArgument) }

    /// UI tests only: what the scripted speech recognizer "hears".
    let scriptedSpeech: ScriptedSpeech?

    struct ScriptedSpeech: Sendable, Equatable {
        let transcript: String
        let availability: SpeechAvailability
    }

    /// UI tests only: `-ui-testing-ai-scripted` uses a fixed AI reply; otherwise AI is unavailable under UI testing.
    static let scriptedAIArgument = "-ui-testing-ai-scripted"
    var usesScriptedAI: Bool { isUITesting && ProcessInfo.processInfo.arguments.contains(Self.scriptedAIArgument) }

    /// UI tests only: the scripted audio service has no voices, so listening is unavailable.
    static let audioNoVoiceArgument = "-ui-testing-audio-no-voice"
    var audioHasNoVoices: Bool { isUITesting && ProcessInfo.processInfo.arguments.contains(Self.audioNoVoiceArgument) }

    /// UI tests only: `-ui-testing-speech "<words>"`, or `-ui-testing-speech-denied`.
    static let speechTranscriptArgument = "-ui-testing-speech"
    static let speechDeniedArgument = "-ui-testing-speech-denied"

    static func current(
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main
    ) -> AppConfiguration {
        let arguments = processInfo.arguments
        let isUITesting = arguments.contains(uiTestingArgument)
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        return AppConfiguration(
            appVersion: version,
            isUITesting: isUITesting,
            splashDuration: isUITesting ? .zero : .milliseconds(1200),
            userDataLocation: userDataLocation(arguments: arguments, isUITesting: isUITesting),
            resetsUserData: isUITesting && arguments.contains(resetUserDataArgument),
            contentManifestURL: contentManifestURL(arguments: arguments, isUITesting: isUITesting,
                                                   infoValue: bundle.object(forInfoDictionaryKey: manifestInfoKey) as? String),
            scriptedSpeech: scriptedSpeech(arguments: arguments, isUITesting: isUITesting)
        )
    }

    static func contentManifestURL(arguments: [String], isUITesting: Bool, infoValue: String?) -> URL? {
        if isUITesting {
            guard let flag = arguments.firstIndex(of: manifestURLArgument), arguments.indices.contains(flag + 1) else { return nil }
            return URL(string: arguments[flag + 1])
        }
        guard let value = infoValue?.trimmingCharacters(in: .whitespaces), !value.isEmpty,
              let url = URL(string: value), url.scheme == "https" else { return nil }
        return url
    }

    /// Downloaded packages: Application Support in production; a temporary folder under UI testing.
    func packagesDirectory() throws(AppError) -> URL {
        isUITesting ? FileManager.default.temporaryDirectory.appending(path: "ui-test-packages", directoryHint: .isDirectory)
                    : try PackageFileStore.defaultDirectory()
    }

    static func scriptedSpeech(arguments: [String], isUITesting: Bool) -> ScriptedSpeech? {
        guard isUITesting else { return nil }
        if arguments.contains(speechDeniedArgument) { return ScriptedSpeech(transcript: "", availability: .denied) }
        guard let flag = arguments.firstIndex(of: speechTranscriptArgument), arguments.indices.contains(flag + 1) else {
            // Never touch the real microphone under automation.
            return ScriptedSpeech(transcript: "", availability: .unsupported)
        }
        return ScriptedSpeech(transcript: arguments[flag + 1], availability: .available)
    }

    /// Production uses SwiftData's default store. UI tests use memory, unless they name a test store,
    /// which lives in the temporary directory and never touches real user data.
    static func userDataLocation(arguments: [String], isUITesting: Bool) -> PersistenceManager.Location {
        guard isUITesting else { return .defaultFile }
        guard let flag = arguments.firstIndex(of: userDataStoreArgument), arguments.indices.contains(flag + 1) else {
            return .inMemory
        }
        let name = arguments[flag + 1].filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !name.isEmpty else { return .inMemory }
        return .file(FileManager.default.temporaryDirectory.appendingPathComponent("\(name).store"))
    }
}
