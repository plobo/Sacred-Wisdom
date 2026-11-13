import Foundation

/// Plays passage audio (spec §11). Implementations: `SystemSpeechAudioService` (AVSpeechSynthesizer),
/// `RecordedAudioService` (licensed audio files), `RoutingAudioService` (picks between them by content) and
/// `ScriptedAudioService` (tests and UI automation).
///
/// One request plays at a time. Starting a new one stops the previous one, whose handler receives `.superseded`.
@MainActor
protocol AudioService: AnyObject {
    /// Installed voices for a language ("en" matches "en-US", "en-GB", ...). Empty for recordings.
    func voices(for languageCode: String) -> [AudioVoice]
    /// Whether this content can be played on this device (a voice exists, or the file is readable).
    func canPlay(_ content: AudioContent) -> Bool
    /// Starts playing from `fraction` (0...1) of the way through.
    func play(_ content: AudioContent, voiceID: String?, speed: Double, from fraction: Double,
              onEvent: @escaping @MainActor (AudioEvent) -> Void) throws(AppError)
    func pause()
    func resume()
    func stop()
}

/// Licensed prerecorded audio (spec §11). A catalog lists only recordings whose license permits playback.
protocol RecordedAudioCatalog: Sendable {
    func recordingURL(passageID: String, translationID: String) async -> URL?
}

/// No recordings are licensed yet, so the app ships an empty catalog and uses text-to-speech.
struct EmptyRecordedAudioCatalog: RecordedAudioCatalog {
    func recordingURL(passageID: String, translationID: String) async -> URL? { nil }
}
