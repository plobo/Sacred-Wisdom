import Foundation
import Observation

/// Listening state for one screen: the passage's track, play/pause, progress, speed and voice (spec §11).
/// The reader and verse details each own one; it plays through the app's single `AudioService`, so starting
/// audio on one screen stops it on another (that controller then shows its track as ready again).
@Observable
@MainActor
final class AudioPlaybackController {
    enum Status: Equatable {
        /// Nothing loaded yet.
        case idle
        /// The passage can't be listened to, with the reason.
        case unavailable(String)
        case ready
        case playing
        case paused
        case finished
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var track: AudioTrack?
    /// Fraction heard, 0...1.
    private(set) var progress: Double = 0
    private(set) var voices: [AudioVoice] = []
    private(set) var selectedVoiceID: String?

    /// Called when a track plays to the end (the reader uses it to go on to the next passage).
    var onFinished: (() -> Void)?

    private let service: any AudioService
    private let preferences: AppPreferences
    /// Set when speed or voice changes while paused: the next resume restarts with the new settings.
    private var needsRestart = false

    init(service: any AudioService, preferences: AppPreferences) {
        self.service = service
        self.preferences = preferences
    }

    var speed: Double { preferences.playbackSpeed }
    var isPlaying: Bool { status == .playing }
    /// Playing or paused: the user is in the middle of listening.
    var isActive: Bool { status == .playing || status == .paused }

    // MARK: Loading

    /// Shows a new passage's audio. Whatever was playing stops; `autoplay` starts the new track at once.
    func load(_ availability: AudioAvailability, autoplay: Bool = false) {
        if isActive { service.stop() }
        progress = 0
        needsRestart = false
        switch availability {
        case .unavailable(let reason):
            track = nil
            voices = []
            status = .unavailable(reason.message)
        case .available(let track):
            self.track = track
            guard service.canPlay(track.content) else {
                voices = []
                status = .unavailable((track.content.languageCode.map { AudioUnavailableReason.noVoice(languageCode: $0) }
                                       ?? .noText).message)
                return
            }
            if let code = track.content.languageCode {
                voices = service.voices(for: code)
                let stored = preferences.voiceID(forLanguage: code)
                selectedVoiceID = voices.contains { $0.id == stored } ? stored : voices.first?.id
            } else {
                voices = []
                selectedVoiceID = nil
            }
            status = .ready
            if autoplay { start(from: 0) }
        }
    }

    // MARK: Transport

    func togglePlayPause() {
        switch status {
        case .playing: pause()
        case .paused: resume()
        case .ready, .finished, .failed: start(from: status == .finished ? 0 : progress)
        case .idle, .unavailable: break
        }
    }

    func pause() {
        guard status == .playing else { return }
        service.pause()
        status = .paused
    }

    func resume() {
        guard status == .paused else { return }
        if needsRestart {
            start(from: progress)
        } else {
            service.resume()
            status = .playing
        }
    }

    /// Stops and rewinds (leaving a screen calls this).
    func stop() {
        guard isActive else { return }
        service.stop()
        status = .ready
        progress = 0
    }

    // MARK: Settings

    func setSpeed(_ speed: Double) {
        let speed = PlaybackSpeed.nearest(to: speed)
        guard speed != preferences.playbackSpeed else { return }
        preferences.playbackSpeed = speed
        applyChangedSettings()
    }

    func selectVoice(_ id: String) {
        guard id != selectedVoiceID, voices.contains(where: { $0.id == id }), let code = track?.content.languageCode else { return }
        selectedVoiceID = id
        preferences.setVoiceID(id, forLanguage: code)
        applyChangedSettings()
    }

    /// Speed and voice are fixed once speech starts, so playing audio restarts where it is.
    private func applyChangedSettings() {
        switch status {
        case .playing: start(from: progress)
        case .paused: needsRestart = true
        default: break
        }
    }

    // MARK: Playback

    private func start(from fraction: Double) {
        guard let track else { return }
        needsRestart = false
        do throws(AppError) {
            try service.play(track.content, voiceID: selectedVoiceID, speed: speed, from: fraction) { [weak self] event in
                self?.handle(event)
            }
            progress = fraction
            status = .playing
        } catch {
            status = .failed(String(localized: "This passage could not be played. Please try again."))
        }
    }

    private func handle(_ event: AudioEvent) {
        switch event {
        case .progress(let value):
            progress = min(max(value, 0), 1)
        case .finished:
            progress = 1
            status = .finished
            onFinished?()
        case .interrupted:
            if status == .playing { status = .paused }
        case .superseded:
            status = .ready
            progress = 0
        case .failed(let message):
            status = .failed(message)
        }
    }

    // MARK: Accessibility

    /// e.g. "Playing, 40 percent".
    var accessibilityStatus: String {
        let percent = Int((progress * 100).rounded())
        return switch status {
        case .playing: String(localized: "Playing, \(percent) percent")
        case .paused: String(localized: "Paused, \(percent) percent")
        case .finished: String(localized: "Finished")
        case .ready: String(localized: "Ready to play")
        case .failed(let message), .unavailable(let message): message
        case .idle: ""
        }
    }
}
