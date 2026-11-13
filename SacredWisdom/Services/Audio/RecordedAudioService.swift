import AVFoundation

/// Plays licensed recordings (local files) with `AVAudioPlayer`. Speed uses the player's rate, so pitch is kept.
@MainActor
final class RecordedAudioService: NSObject, AudioService {
    private struct Request {
        let player: AVAudioPlayer
        let onEvent: @MainActor (AudioEvent) -> Void
    }

    private let session: AudioSessionController
    private var current: Request?
    private var ticker: Timer?

    init(session: AudioSessionController) {
        self.session = session
        super.init()
        session.addInterruptionHandler { [weak self] in self?.interrupt() }
    }

    func voices(for languageCode: String) -> [AudioVoice] { [] }

    func canPlay(_ content: AudioContent) -> Bool {
        guard case .recording(let url) = content else { return false }
        return url.isFileURL && FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false))
    }

    func play(_ content: AudioContent, voiceID: String?, speed: Double, from fraction: Double,
              onEvent: @escaping @MainActor (AudioEvent) -> Void) throws(AppError) {
        guard case .recording(let url) = content else { throw .unexpected("Recording service asked to speak text") }
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: url)
        } catch {
            throw .contentCorrupted("recording \(url.lastPathComponent)")
        }
        supersede()
        player.delegate = self
        player.enableRate = true
        player.rate = Float(speed)
        player.currentTime = player.duration * min(max(fraction, 0), 1)
        session.activate()
        current = Request(player: player, onEvent: onEvent)
        guard player.play() else {
            current = nil
            throw .unexpected("recording did not start")
        }
        startTicker()
    }

    func pause() {
        current?.player.pause()
        ticker?.invalidate()
    }

    func resume() {
        guard let current else { return }
        session.activate()
        current.player.play()
        startTicker()
    }

    func stop() {
        ticker?.invalidate()
        current?.player.stop()
        current = nil
        session.deactivate()
    }

    private func supersede() {
        guard let previous = current else { return }
        ticker?.invalidate()
        previous.player.stop()
        current = nil
        previous.onEvent(.superseded)
    }

    private func interrupt() {
        guard let current, current.player.isPlaying else { return }
        pause()
        current.onEvent(.interrupted)
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportProgress() }
        }
    }

    private func reportProgress() {
        guard let current, current.player.duration > 0 else { return }
        current.onEvent(.progress(min(1, current.player.currentTime / current.player.duration)))
    }

    fileprivate func didFinish(_ player: ObjectIdentifier, successfully: Bool) {
        guard let finished = current, ObjectIdentifier(finished.player) == player else { return }
        ticker?.invalidate()
        current = nil
        session.deactivate()
        if successfully {
            finished.onEvent(.progress(1))
            finished.onEvent(.finished)
        } else {
            finished.onEvent(.failed(String(localized: "The recording could not be played.")))
        }
    }
}

extension RecordedAudioService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.didFinish(id, successfully: flag) }
    }
}

/// Sends each request to the service that can play it: recordings to `RecordedAudioService`, text to speech.
/// A new request on either one stops whatever the other was playing.
@MainActor
final class RoutingAudioService: AudioService {
    private let speech: any AudioService
    private let recordings: any AudioService
    private var active: (any AudioService)?
    private var activeHandler: (@MainActor (AudioEvent) -> Void)?
    private var token = 0

    init(speech: any AudioService, recordings: any AudioService) {
        self.speech = speech
        self.recordings = recordings
    }

    private func service(for content: AudioContent) -> any AudioService {
        if case .recording = content { return recordings }
        return speech
    }

    func voices(for languageCode: String) -> [AudioVoice] { speech.voices(for: languageCode) }

    func canPlay(_ content: AudioContent) -> Bool { service(for: content).canPlay(content) }

    func play(_ content: AudioContent, voiceID: String?, speed: Double, from fraction: Double,
              onEvent: @escaping @MainActor (AudioEvent) -> Void) throws(AppError) {
        let target = service(for: content)
        let mine = token + 1
        // Only this router reports `.superseded` (services' own reports are dropped), so a request is told once
        // however the previous one was stopped. Events from earlier requests are dropped by token.
        try target.play(content, voiceID: voiceID, speed: speed, from: fraction) { [weak self] event in
            guard let self, self.token == mine, event != .superseded else { return }
            onEvent(event)
        }
        if let active, active !== target { active.stop() }
        let previous = activeHandler
        token = mine
        active = target
        activeHandler = onEvent
        previous?(.superseded)
    }

    func pause() { active?.pause() }
    func resume() { active?.resume() }

    func stop() {
        token += 1
        active?.stop()
        active = nil
        activeHandler = nil
    }
}
