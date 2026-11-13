import Observation
import SwiftUI

/// Display preferences that apply app-wide, persisted in UserDefaults.
@Observable
@MainActor
final class AppPreferences {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    static let appearanceKey = "appearance"
    static let readerTextScaleKey = "readerTextScale"

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    /// Default scripture text size in the reader (it still follows Dynamic Type; this multiplies it).
    var readerTextScale: Double {
        didSet { defaults.set(readerTextScale, forKey: Self.readerTextScaleKey) }
    }

    static let playbackSpeedKey = "playbackSpeed"
    static let continuousPlaybackKey = "continuousPlayback"
    static let voiceKeyPrefix = "voice."

    /// Listening speed for passage audio (one of `PlaybackSpeed.all`).
    var playbackSpeed: Double {
        didSet { defaults.set(playbackSpeed, forKey: Self.playbackSpeedKey) }
    }

    /// In the reader, go on to the next passage when one finishes playing.
    var continuousPlayback: Bool {
        didSet { defaults.set(continuousPlayback, forKey: Self.continuousPlaybackKey) }
    }

    /// The chosen text-to-speech voice for a language ("en"); nil means the system's best voice.
    func voiceID(forLanguage code: String) -> String? {
        defaults.string(forKey: Self.voiceKey(code))
    }

    func setVoiceID(_ id: String?, forLanguage code: String) {
        defaults.set(id, forKey: Self.voiceKey(code))
    }

    private static func voiceKey(_ code: String) -> String {
        voiceKeyPrefix + (code.split(separator: "-").first.map(String.init) ?? code).lowercased()
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
        let stored = defaults.double(forKey: Self.readerTextScaleKey)
        readerTextScale = stored == 0 ? 1 : min(max(stored, ReaderViewModel.fontScaleRange.lowerBound),
                                                ReaderViewModel.fontScaleRange.upperBound)
        let speed = defaults.double(forKey: Self.playbackSpeedKey)
        playbackSpeed = speed == 0 ? PlaybackSpeed.default : PlaybackSpeed.nearest(to: speed)
        continuousPlayback = defaults.object(forKey: Self.continuousPlaybackKey) as? Bool ?? true
    }
}
