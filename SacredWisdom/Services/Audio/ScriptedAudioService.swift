import Foundation

/// An audio service with no sound, for unit tests and UI automation (simulators under test have no audible
/// output to check). It records every call. With a `duration` it plays by itself, reporting progress in tenths
/// and then finishing; without one, tests drive it with `emit(_:)`.
@MainActor
final class ScriptedAudioService: AudioService {
    struct Play: Equatable {
        let content: AudioContent
        let voiceID: String?
        let speed: Double
        let fraction: Double
    }

    private(set) var plays: [Play] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    private(set) var isPaused = false

    var installedVoices: [AudioVoice]
    /// Languages with a voice; recordings are always playable.
    var voicedLanguages: Set<String>
    var failure: AppError?

    private let duration: Duration?
    private var handler: (@MainActor (AudioEvent) -> Void)?
    private var progress = 0.0
    private var ticker: Task<Void, Never>?

    init(voices: [AudioVoice] = ScriptedAudioService.defaultVoices, voicedLanguages: Set<String> = ["en"],
         duration: Duration? = nil) {
        installedVoices = voices
        self.voicedLanguages = voicedLanguages
        self.duration = duration
    }

    static let defaultVoices = [
        AudioVoice(id: "scripted.voice.us", name: "Avery", languageCode: "en-US", isEnhanced: true),
        AudioVoice(id: "scripted.voice.gb", name: "Rowan", languageCode: "en-GB", isEnhanced: false),
    ]

    func voices(for languageCode: String) -> [AudioVoice] {
        guard voicedLanguages.contains(Self.base(languageCode)) else { return [] }
        return installedVoices.filter { Self.base($0.languageCode) == Self.base(languageCode) }
    }

    func canPlay(_ content: AudioContent) -> Bool {
        switch content {
        case .recording: true
        case .speech(let text, let code): !text.isEmpty && voicedLanguages.contains(Self.base(code))
        }
    }

    func play(_ content: AudioContent, voiceID: String?, speed: Double, from fraction: Double,
              onEvent: @escaping @MainActor (AudioEvent) -> Void) throws(AppError) {
        if let failure { throw failure }
        let previous = handler
        ticker?.cancel()
        plays.append(Play(content: content, voiceID: voiceID, speed: speed, fraction: fraction))
        handler = onEvent
        progress = fraction
        isPaused = false
        previous?(.superseded)
        startTicker()
    }

    func pause() {
        pauseCount += 1
        isPaused = true
        ticker?.cancel()
    }

    func resume() {
        resumeCount += 1
        isPaused = false
        startTicker()
    }

    func stop() {
        stopCount += 1
        ticker?.cancel()
        handler = nil
    }

    /// Sends an event to the current request.
    func emit(_ event: AudioEvent) {
        handler?(event)
        if event == .finished { handler = nil }
    }

    private func startTicker() {
        guard let duration else { return }
        let step = duration / 10
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: step)
                guard !Task.isCancelled, let self else { return }
                self.progress = min(1, self.progress + 0.1)
                self.handler?(.progress(self.progress))
                if self.progress >= 0.999 {
                    self.emit(.finished)
                    return
                }
            }
        }
    }

    private static func base(_ code: String) -> String {
        String(code.split(separator: "-").first ?? Substring(code)).lowercased()
    }
}
