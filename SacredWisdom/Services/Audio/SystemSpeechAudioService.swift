import AVFoundation

/// Text-to-speech with `AVSpeechSynthesizer`. Runs entirely on the device.
///
/// Speed changes and voice changes restart from the current position (`from fraction`), because an utterance's
/// rate and voice are fixed once it starts. Progress is reported against the whole text, not the remaining part.
@MainActor
final class SystemSpeechAudioService: NSObject, AudioService {
    private struct Request {
        let utterance: ObjectIdentifier
        /// UTF-16 length of the whole text and where this utterance starts within it.
        let fullLength: Int
        let offset: Int
        let onEvent: @MainActor (AudioEvent) -> Void
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let session: AudioSessionController
    private var current: Request?

    init(session: AudioSessionController) {
        self.session = session
        super.init()
        synthesizer.delegate = self
        session.addInterruptionHandler { [weak self] in self?.interrupt() }
    }

    func voices(for languageCode: String) -> [AudioVoice] {
        Self.matchingVoices(languageCode).map {
            AudioVoice(id: $0.identifier, name: $0.name, languageCode: $0.language, isEnhanced: $0.quality != .default)
        }
    }

    func canPlay(_ content: AudioContent) -> Bool {
        guard case .speech(let text, let code) = content else { return false }
        return !text.isEmpty && !Self.matchingVoices(code).isEmpty
    }

    func play(_ content: AudioContent, voiceID: String?, speed: Double, from fraction: Double,
              onEvent: @escaping @MainActor (AudioEvent) -> Void) throws(AppError) {
        guard case .speech(let text, let code) = content else {
            throw .unexpected("Speech service asked to play a recording")
        }
        guard let voice = Self.voice(id: voiceID, languageCode: code) else {
            throw .contentNotFound("voice for \(code)")
        }
        supersede()
        let full = text as NSString
        let offset = Self.wordStart(in: full, near: fraction)
        let utterance = AVSpeechUtterance(string: full.substring(from: offset))
        utterance.voice = voice
        utterance.rate = Self.rate(for: speed)
        utterance.prefersAssistiveTechnologySettings = false
        session.activate()
        current = Request(utterance: ObjectIdentifier(utterance), fullLength: max(full.length, 1), offset: offset,
                          onEvent: onEvent)
        Log.audio.info("Speaking \(full.length - offset, privacy: .public) characters at \(speed, privacy: .public)×")
        synthesizer.speak(utterance)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        session.activate()
        synthesizer.continueSpeaking()
    }

    func stop() {
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
        session.deactivate()
    }

    private func supersede() {
        guard let previous = current else { return }
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
        previous.onEvent(.superseded)
    }

    private func interrupt() {
        guard let current, synthesizer.isSpeaking, !synthesizer.isPaused else { return }
        synthesizer.pauseSpeaking(at: .immediate)
        current.onEvent(.interrupted)
    }

    // MARK: Delegate callbacks (hop to the main actor; ignore utterances that are no longer current)

    fileprivate func didReach(_ end: Int, utterance: ObjectIdentifier) {
        guard let current, current.utterance == utterance else { return }
        current.onEvent(.progress(min(1, Double(current.offset + end) / Double(current.fullLength))))
    }

    fileprivate func didFinish(utterance: ObjectIdentifier) {
        guard let finished = current, finished.utterance == utterance else { return }
        current = nil
        session.deactivate()
        finished.onEvent(.progress(1))
        finished.onEvent(.finished)
    }

    // MARK: Helpers

    /// Installed voices for a language, best first: the user's region, then enhanced quality. Novelty and
    /// Personal Voices are left out.
    static func matchingVoices(_ languageCode: String) -> [AVSpeechSynthesisVoice] {
        let base = languageCode.split(separator: "-").first.map(String.init)?.lowercased() ?? languageCode
        let preferredRegion = AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                let language = voice.language.lowercased()
                return (language == base || language.hasPrefix(base + "-"))
                    && !voice.voiceTraits.contains(.isNoveltyVoice)
                    && !voice.voiceTraits.contains(.isPersonalVoice)
            }
            .sorted { lhs, rhs in
                let lhsRegion = lhs.language == preferredRegion, rhsRegion = rhs.language == preferredRegion
                if lhsRegion != rhsRegion { return lhsRegion }
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name < rhs.name
            }
    }

    static func voice(id: String?, languageCode: String) -> AVSpeechSynthesisVoice? {
        let candidates = matchingVoices(languageCode)
        return candidates.first { $0.identifier == id } ?? candidates.first
    }

    /// Maps 0.75×...1.5× onto the synthesizer's rate scale around its default rate.
    static func rate(for speed: Double) -> Float {
        let rate = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
        return min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    /// The UTF-16 offset of the word at `fraction` of the way through, so restarts never begin mid-word.
    static func wordStart(in text: NSString, near fraction: Double) -> Int {
        guard fraction > 0, text.length > 0 else { return 0 }
        var index = min(text.length - 1, Int(Double(text.length) * min(fraction, 1)))
        let whitespace = CharacterSet.whitespacesAndNewlines
        while index > 0, let scalar = Unicode.Scalar(text.character(at: index - 1)), !whitespace.contains(scalar) {
            index -= 1
        }
        // Low surrogates are not scalars on their own; never split a pair.
        if index > 0, CFStringIsSurrogateLowCharacter(text.character(at: index)) { index -= 1 }
        return index
    }
}

extension SystemSpeechAudioService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance), end = characterRange.upperBound
        Task { @MainActor in self.didReach(end, utterance: id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.didFinish(utterance: id) }
    }
}

/// The app's audio session: spoken-audio playback that is heard with the ring/silent switch on silent.
/// Reports interruptions (calls, alarms) so playback pauses instead of silently stopping.
@MainActor
final class AudioSessionController {
    private var handlers: [() -> Void] = []
    private var observer: (any NSObjectProtocol)?

    func addInterruptionHandler(_ handler: @escaping () -> Void) {
        handlers.append(handler)
        observeInterruptionsIfNeeded()
    }

    func activate() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            Log.audio.error("Audio session activation failed: \(String(describing: error), privacy: .public)")
        }
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeInterruptionsIfNeeded() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated { self?.handlers.forEach { $0() } }
        }
    }
}
