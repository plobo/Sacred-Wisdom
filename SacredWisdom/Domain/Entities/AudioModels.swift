import Foundation

/// What an audio service plays for one passage.
enum AudioContent: Equatable, Sendable {
    /// A licensed recording (bundled or downloaded file).
    case recording(URL)
    /// System text-to-speech of verified passage text, in that text's language.
    case speech(text: String, languageCode: String)

    var languageCode: String? {
        if case .speech(_, let code) = self { return code }
        return nil
    }
}

/// One passage, in one translation, ready to play.
struct AudioTrack: Identifiable, Equatable, Sendable {
    let passageID: String
    let reference: String
    let translationID: String
    /// Translation (or recording) name shown in the player.
    let title: String
    let content: AudioContent

    var id: String { "\(passageID)|\(translationID)" }
    var isRecording: Bool {
        if case .recording = content { return true }
        return false
    }
}

/// Why a passage cannot be listened to.
enum AudioUnavailableReason: Equatable, Sendable {
    /// The text's license does not clearly permit making audio from it (spec §11).
    case licenseNotPermitted(sourceName: String)
    /// The passage has no text in that translation.
    case noText
    /// The device has no text-to-speech voice for the language.
    case noVoice(languageCode: String)

    var message: String {
        switch self {
        case .licenseNotPermitted(let source):
            String(localized: "Listening isn't available: the license for \(source) doesn't permit audio.")
        case .noText:
            String(localized: "There is no text to listen to.")
        case .noVoice(let code):
            String(localized: "No voice is installed for \(LanguageInfo.displayName(code)). You can add one in Settings → Accessibility → Spoken Content.")
        }
    }
}

enum AudioAvailability: Equatable, Sendable {
    case available(AudioTrack)
    case unavailable(AudioUnavailableReason)
}

/// A text-to-speech voice installed on the device.
struct AudioVoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// BCP 47 language tag, e.g. "en-GB".
    let languageCode: String
    let isEnhanced: Bool

    /// e.g. "Daniel (English, United Kingdom)".
    var displayName: String {
        let region = Locale.current.localizedString(forIdentifier: languageCode) ?? languageCode
        return "\(name) (\(region))"
    }
}

/// Playback speeds offered in the player and Settings.
enum PlaybackSpeed {
    static let all: [Double] = [0.75, 1.0, 1.25, 1.5]
    static let `default` = 1.0

    static func label(_ speed: Double) -> String {
        speed.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    static func nearest(to value: Double) -> Double {
        all.min { abs($0 - value) < abs($1 - value) } ?? Self.default
    }
}

/// What an audio service reports while it plays.
enum AudioEvent: Equatable, Sendable {
    /// Fraction of the track heard so far, 0...1.
    case progress(Double)
    case finished
    /// Playback was paused by the system (an interruption such as a call).
    case interrupted
    /// Another request took over the audio service; this one stopped.
    case superseded
    case failed(String)
}
