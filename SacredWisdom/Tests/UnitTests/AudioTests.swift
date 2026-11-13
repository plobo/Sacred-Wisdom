import AVFoundation
import Foundation
import Testing
@testable import SacredWisdom

// MARK: - License policy

@Suite struct AudioLicensePolicyTests {
    private func source(_ license: String) -> ContentSource {
        ContentSource(id: "s", name: "Source", url: nil, license: license, attribution: "")
    }

    @Test(arguments: [
        "Public domain",
        "Public domain (Crown rights apply in the United Kingdom)",
        "public domain",
        "Translation: CC0 1.0. Pali root text: ancient canon (digital edition license to be confirmed)",
        "CC BY 4.0",
        "CC BY-SA 4.0",
        "Licensed under CC-BY 3.0",
    ])
    func permitsOpenLicenses(_ license: String) {
        #expect(AudioLicensePolicy.allowsSynthesizedSpeech(source(license)))
    }

    @Test(arguments: [
        "Tanzil license: verbatim copies permitted with attribution; changes not allowed",
        "CC BY-ND 4.0",
        "CC BY-NC-SA 4.0",
        "CC BY-NC 4.0",
        "All rights reserved",
        "Used by permission and with care",
        "N/A",
        "",
    ])
    func refusesEverythingElse(_ license: String) {
        #expect(!AudioLicensePolicy.allowsSynthesizedSpeech(source(license)))
    }
}

// MARK: - Track resolution

private struct FixedRecordings: RecordedAudioCatalog {
    let url: URL?
    func recordingURL(passageID: String, translationID: String) async -> URL? { url }
}

@Suite struct ResolveAudioTrackUseCaseTests {
    private func passage(license: String, texts: [(String, String)] = [("t1", "  First text. "), ("t2", "Second text.")]) -> ScripturePassage {
        let source = ContentSource(id: "src", name: "Fixture Source", url: nil, license: license, attribution: "")
        return ScripturePassage(
            id: "p1", religionID: "r1", collectionID: "c1", bookID: "b1", sectionID: "s1", sequence: 1,
            reference: "REF 1", originalLanguage: "ar", originalText: "[original]", originalSource: source,
            texts: texts.map { id, text in
                PassageText(translation: Translation(id: id, collectionID: "c1", name: id.uppercased(), languageCode: "en",
                                                     translator: "x", year: nil, source: source), text: text)
            }
        )
    }

    @Test func speaksTheRequestedTranslationVerbatimTrimmed() async {
        let result = await ResolveAudioTrackUseCase().execute(passage: passage(license: "Public domain"), translationID: "t2")
        #expect(result == .available(AudioTrack(passageID: "p1", reference: "REF 1", translationID: "t2", title: "T2",
                                                content: .speech(text: "Second text.", languageCode: "en"))))
        let first = await ResolveAudioTrackUseCase().execute(passage: passage(license: "Public domain"), translationID: nil)
        guard case .available(let track) = first else { Issue.record("expected a track"); return }
        #expect(track.content == .speech(text: "First text.", languageCode: "en"))
    }

    @Test func unknownTranslationFallsBackToDefault() async {
        let result = await ResolveAudioTrackUseCase().execute(passage: passage(license: "Public domain"), translationID: "missing")
        guard case .available(let track) = result else { Issue.record("expected a track"); return }
        #expect(track.translationID == "t1")
    }

    @Test func refusesUnlicensedText() async {
        let result = await ResolveAudioTrackUseCase().execute(passage: passage(license: "All rights reserved"), translationID: "t1")
        #expect(result == .unavailable(.licenseNotPermitted(sourceName: "Fixture Source")))
    }

    @Test func licensedRecordingWinsEvenWhenSpeechIsRefused() async {
        let url = URL(filePath: "/tmp/recording.m4a")
        let result = await ResolveAudioTrackUseCase(recordings: FixedRecordings(url: url))
            .execute(passage: passage(license: "All rights reserved"), translationID: "t1")
        guard case .available(let track) = result else { Issue.record("expected a track"); return }
        #expect(track.content == .recording(url))
        #expect(track.isRecording)
    }

    @Test func emptyTextIsUnavailable() async {
        let result = await ResolveAudioTrackUseCase().execute(passage: passage(license: "Public domain", texts: [("t1", "   ")]),
                                                             translationID: nil)
        #expect(result == .unavailable(.noText))
        let none = await ResolveAudioTrackUseCase().execute(passage: passage(license: "Public domain", texts: []), translationID: nil)
        #expect(none == .unavailable(.noText))
    }

    @Test func originalTextIsNeverSpoken() async {
        let result = await ResolveAudioTrackUseCase().execute(passage: passage(license: "Public domain"), translationID: nil)
        guard case .available(let track) = result, case .speech(let text, let code) = track.content else {
            Issue.record("expected speech"); return
        }
        #expect(!text.contains("[original]"))
        #expect(code == "en")
    }
}

// MARK: - Playback controller

@MainActor
@Suite struct AudioPlaybackControllerTests {
    private let track = AudioTrack(passageID: "p1", reference: "REF 1", translationID: "t1", title: "T1",
                                   content: .speech(text: "Some words here.", languageCode: "en"))

    private func make(_ service: ScriptedAudioService = ScriptedAudioService()) -> (AudioPlaybackController, ScriptedAudioService, AppPreferences) {
        let preferences = AppPreferences(defaults: AppDependencies.volatileDefaults())
        return (AudioPlaybackController(service: service, preferences: preferences), service, preferences)
    }

    @Test func loadsVoicesAndStartsReady() {
        let (controller, _, _) = make()
        #expect(controller.status == .idle)
        controller.load(.available(track))
        #expect(controller.status == .ready)
        #expect(controller.voices.map(\.id) == ["scripted.voice.us", "scripted.voice.gb"])
        #expect(controller.selectedVoiceID == "scripted.voice.us")
    }

    @Test func playPauseResumeAndProgress() {
        let (controller, service, _) = make()
        controller.load(.available(track))
        controller.togglePlayPause()
        #expect(controller.status == .playing)
        #expect(service.plays == [.init(content: track.content, voiceID: "scripted.voice.us", speed: 1, fraction: 0)])
        service.emit(.progress(0.4))
        #expect(controller.progress == 0.4)
        #expect(controller.accessibilityStatus == "Playing, 40 percent")
        controller.togglePlayPause()
        #expect(controller.status == .paused)
        #expect(service.pauseCount == 1)
        controller.togglePlayPause()
        #expect(controller.status == .playing)
        #expect(service.resumeCount == 1)
        #expect(service.plays.count == 1)
    }

    @Test func speedChangeRestartsWherePlaybackIs() {
        let (controller, service, preferences) = make()
        controller.load(.available(track))
        controller.togglePlayPause()
        service.emit(.progress(0.5))
        controller.setSpeed(1.5)
        #expect(preferences.playbackSpeed == 1.5)
        #expect(service.plays.last == .init(content: track.content, voiceID: "scripted.voice.us", speed: 1.5, fraction: 0.5))
        #expect(controller.status == .playing)
    }

    @Test func settingsChangedWhilePausedApplyOnResume() {
        let (controller, service, preferences) = make()
        controller.load(.available(track))
        controller.togglePlayPause()
        service.emit(.progress(0.3))
        controller.pause()
        controller.selectVoice("scripted.voice.gb")
        controller.setSpeed(0.75)
        #expect(service.plays.count == 1)
        #expect(preferences.voiceID(forLanguage: "en-US") == "scripted.voice.gb")
        controller.resume()
        #expect(service.resumeCount == 0)
        #expect(service.plays.last == .init(content: track.content, voiceID: "scripted.voice.gb", speed: 0.75, fraction: 0.3))
    }

    @Test func rememberedVoiceIsUsedNextTime() {
        let (controller, _, preferences) = make()
        preferences.setVoiceID("scripted.voice.gb", forLanguage: "en")
        controller.load(.available(track))
        #expect(controller.selectedVoiceID == "scripted.voice.gb")
        preferences.setVoiceID("uninstalled", forLanguage: "en")
        controller.load(.available(track))
        #expect(controller.selectedVoiceID == "scripted.voice.us")
    }

    @Test func finishingCallsBackAndReplaysFromStart() {
        let (controller, service, _) = make()
        var finished = 0
        controller.onFinished = { finished += 1 }
        controller.load(.available(track))
        controller.togglePlayPause()
        service.emit(.progress(0.9))
        service.emit(.finished)
        #expect(controller.status == .finished)
        #expect(controller.progress == 1)
        #expect(finished == 1)
        controller.togglePlayPause()
        #expect(service.plays.last?.fraction == 0)
    }

    @Test func noVoiceForLanguageIsUnavailable() {
        let (controller, _, _) = make(ScriptedAudioService(voicedLanguages: []))
        controller.load(.available(track))
        #expect(controller.status == .unavailable(AudioUnavailableReason.noVoice(languageCode: "en").message))
        controller.togglePlayPause()
        #expect(controller.status == .unavailable(AudioUnavailableReason.noVoice(languageCode: "en").message))
    }

    @Test func unlicensedIsUnavailableWithReason() {
        let (controller, service, _) = make()
        controller.load(.unavailable(.licenseNotPermitted(sourceName: "Tanzil")))
        guard case .unavailable(let message) = controller.status else { Issue.record("expected unavailable"); return }
        #expect(message.contains("Tanzil"))
        controller.togglePlayPause()
        #expect(service.plays.isEmpty)
    }

    @Test func anotherScreenPlayingResetsThisOne() {
        let service = ScriptedAudioService()
        let (first, _, _) = make(service)
        let (second, _, _) = make(service)
        first.load(.available(track))
        second.load(.available(track))
        first.togglePlayPause()
        service.emit(.progress(0.6))
        second.togglePlayPause()
        #expect(first.status == .ready)
        #expect(first.progress == 0)
        #expect(second.status == .playing)
    }

    @Test func interruptionPausesAndFailureIsShown() {
        let (controller, service, _) = make()
        controller.load(.available(track))
        controller.togglePlayPause()
        service.emit(.interrupted)
        #expect(controller.status == .paused)
        service.failure = .unexpected("no output")
        controller.load(.available(track))
        controller.togglePlayPause()
        #expect(controller.status == .failed("This passage could not be played. Please try again."))
    }

    @Test func stopRewindsAndLoadingStopsPlayback() {
        let (controller, service, _) = make()
        controller.load(.available(track))
        controller.togglePlayPause()
        service.emit(.progress(0.5))
        controller.stop()
        #expect(controller.status == .ready)
        #expect(controller.progress == 0)
        #expect(service.stopCount == 1)
        controller.togglePlayPause()
        controller.load(.available(track))
        #expect(service.stopCount == 2)
        #expect(controller.status == .ready)
    }

    @Test func speedSnapsToOfferedValues() {
        let (controller, _, preferences) = make()
        controller.setSpeed(1.3)
        #expect(preferences.playbackSpeed == 1.25)
        #expect(PlaybackSpeed.label(1.25) == "1.25×")
        #expect(PlaybackSpeed.label(1) == "1×")
    }
}

// MARK: - Preferences

@MainActor
@Suite struct AudioPreferencesTests {
    @Test func defaultsAndPersistence() {
        let defaults = AppDependencies.volatileDefaults()
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.playbackSpeed == 1)
        #expect(preferences.continuousPlayback)
        preferences.playbackSpeed = 1.5
        preferences.continuousPlayback = false
        preferences.setVoiceID("v", forLanguage: "en-GB")
        let reloaded = AppPreferences(defaults: defaults)
        #expect(reloaded.playbackSpeed == 1.5)
        #expect(!reloaded.continuousPlayback)
        #expect(reloaded.voiceID(forLanguage: "en") == "v")
    }

    @Test func corruptStoredSpeedSnaps() {
        let defaults = AppDependencies.volatileDefaults()
        defaults.set(9.0, forKey: AppPreferences.playbackSpeedKey)
        #expect(AppPreferences(defaults: defaults).playbackSpeed == 1.5)
    }
}

// MARK: - Services

@MainActor
@Suite struct AudioServiceTests {
    @Test func restartsBeginAtAWord() {
        let text = "Blessed are the peacemakers" as NSString
        #expect(SystemSpeechAudioService.wordStart(in: text, near: 0) == 0)
        #expect(SystemSpeechAudioService.wordStart(in: text, near: 0.5) == 12) // inside "the" → its start
        #expect(SystemSpeechAudioService.wordStart(in: text, near: 1) == 16)
        #expect(SystemSpeechAudioService.wordStart(in: "" as NSString, near: 0.5) == 0)
    }

    @Test func rateFollowsSpeedWithinLimits() {
        #expect(SystemSpeechAudioService.rate(for: 1) == AVSpeechUtteranceDefaultSpeechRate)
        #expect(SystemSpeechAudioService.rate(for: 1.5) > SystemSpeechAudioService.rate(for: 1))
        #expect(SystemSpeechAudioService.rate(for: 0.75) < SystemSpeechAudioService.rate(for: 1))
        #expect(SystemSpeechAudioService.rate(for: 100) == AVSpeechUtteranceMaximumSpeechRate)
    }

    @Test func routerSendsEachKindToItsServiceAndSupersedesOnce() throws {
        let speech = ScriptedAudioService(), recordings = ScriptedAudioService()
        let router = RoutingAudioService(speech: speech, recordings: recordings)
        var firstEvents: [AudioEvent] = [], secondEvents: [AudioEvent] = []
        try router.play(.speech(text: "words", languageCode: "en"), voiceID: nil, speed: 1, from: 0) { firstEvents.append($0) }
        speech.emit(.progress(0.2))
        try router.play(.recording(URL(filePath: "/tmp/a.m4a")), voiceID: nil, speed: 1, from: 0) { secondEvents.append($0) }
        speech.emit(.progress(0.9)) // stale: the first request already stopped
        recordings.emit(.progress(0.1))
        #expect(speech.plays.count == 1 && recordings.plays.count == 1)
        #expect(speech.stopCount == 1)
        #expect(firstEvents == [.progress(0.2), .superseded])
        #expect(secondEvents == [.progress(0.1)])

        try router.play(.recording(URL(filePath: "/tmp/b.m4a")), voiceID: nil, speed: 1, from: 0) { _ in }
        #expect(secondEvents == [.progress(0.1), .superseded])
    }

    @Test func recordingServicePlaysAFileToTheEnd() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "tone-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeTone(to: url, seconds: 0.3)
        let service = RecordedAudioService(session: AudioSessionController())
        #expect(service.canPlay(.recording(url)))
        #expect(!service.canPlay(.recording(url.appending(path: "missing"))))
        #expect(!service.canPlay(.speech(text: "x", languageCode: "en")))

        var events: [AudioEvent] = []
        try service.play(.recording(url), voiceID: nil, speed: 1.5, from: 0) { events.append($0) }
        for _ in 0..<40 where !events.contains(.finished) { try await Task.sleep(for: .milliseconds(100)) }
        #expect(events.last == .finished)
        #expect(events.dropLast().last == .progress(1))
    }

    @Test func unreadableRecordingThrows() {
        let service = RecordedAudioService(session: AudioSessionController())
        let url = FileManager.default.temporaryDirectory.appending(path: "not-audio-\(UUID().uuidString).caf")
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: Data("not audio".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: AppError.self) {
            try service.play(.recording(url), voiceID: nil, speed: 1, from: 0) { _ in }
        }
    }

    /// A short sine tone: synthetic test audio, not scripture.
    static func writeTone(to url: URL, seconds: Double) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try #require(buffer.floatChannelData?[0])
        for frame in 0..<Int(frames) { samples[frame] = 0.2 * sin(Float(frame) * 2 * .pi * 440 / 44_100) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}

// MARK: - Screens

/// Speaks every passage's displayed text, whatever its license (fixture sources say "N/A").
struct SpeakEverythingResolver: ResolveAudioTrackUseCaseProtocol {
    func execute(passage: ScripturePassage, translationID: String?) async -> AudioAvailability {
        guard let text = passage.text(preferring: translationID) else { return .unavailable(.noText) }
        return .available(AudioTrack(passageID: passage.id, reference: passage.reference, translationID: text.translation.id,
                                     title: text.translation.name, content: .speech(text: text.text, languageCode: "en")))
    }
}

@MainActor
@Suite struct ListeningScreenTests {
    private func reader(continuous: Bool = true) throws -> (ReaderViewModel, ScriptedAudioService) {
        let service = ScriptedAudioService()
        let preferences = AppPreferences(defaults: AppDependencies.volatileDefaults())
        preferences.continuousPlayback = continuous
        let vm = ReaderViewModel(
            start: .section("s1a"),
            loadPage: LoadReaderPageUseCase(repository: try Fixtures.repository()),
            preferences: InMemoryTranslationPreferenceStore(),
            display: preferences,
            audio: AudioPlaybackController(service: service, preferences: preferences),
            resolveAudio: SpeakEverythingResolver()
        )
        return (vm, service)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<50 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func readerLoadsTheShownPassageWithoutPlaying() async throws {
        let (vm, service) = try reader()
        await vm.load()
        #expect(vm.audio?.track?.passageID == "p1")
        #expect(vm.audio?.status == .ready)
        #expect(service.plays.isEmpty)
    }

    @Test func finishedPassageContinuesToTheNext() async throws {
        let (vm, service) = try reader()
        await vm.load()
        vm.audio?.togglePlayPause()
        service.emit(.finished)
        try await waitUntil { vm.page?.passage.id == "p2" && vm.audio?.isPlaying == true }
        #expect(vm.page?.passage.id == "p2")
        #expect(vm.audio?.isPlaying == true)
        #expect(service.plays.last?.content == .speech(text: "[t1-2]", languageCode: "en"))
    }

    @Test func continuousPlaybackCanBeTurnedOff() async throws {
        let (vm, service) = try reader(continuous: false)
        await vm.load()
        vm.audio?.togglePlayPause()
        service.emit(.finished)
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.page?.passage.id == "p1")
        #expect(vm.audio?.status == .finished)
    }

    @Test func navigatingWhilePlayingKeepsListening() async throws {
        let (vm, service) = try reader()
        await vm.load()
        await vm.goToNext()
        #expect(vm.audio?.status == .ready) // not playing: just loads
        vm.audio?.togglePlayPause()
        await vm.goToNext()
        #expect(vm.page?.passage.id == "p3")
        #expect(vm.audio?.isPlaying == true)
        #expect(service.plays.map(\.content) == [.speech(text: "[t1-2]", languageCode: "en"),
                                                 .speech(text: "[t1-3]", languageCode: "en")])
    }

    @Test func translationChangeSwitchesTheTrackAndLeavingStops() async throws {
        let (vm, service) = try reader()
        await vm.load()
        vm.audio?.togglePlayPause()
        await vm.selectTranslation("t2")
        #expect(vm.audio?.track?.translationID == "t2")
        #expect(service.plays.last?.content == .speech(text: "[t2-1]", languageCode: "en"))
        vm.stopListening()
        #expect(vm.audio?.status == .ready)
        #expect(service.stopCount >= 1)
    }

    @Test func detailListensToPrimaryThenChosenTranslation() async throws {
        let service = ScriptedAudioService()
        let preferences = AppPreferences(defaults: AppDependencies.volatileDefaults())
        let repo = try Fixtures.repository()
        let vm = PassageDetailViewModel(
            passageID: "p1", initialTranslationID: "t2",
            loadDetail: LoadPassageDetailUseCase(scripture: repo, related: repo),
            preferences: InMemoryTranslationPreferenceStore(), userData: try Fixtures.userData(),
            audio: AudioPlaybackController(service: service, preferences: preferences),
            resolveAudio: SpeakEverythingResolver()
        )
        await vm.load()
        #expect(vm.audioTranslationID == "t2")
        #expect(vm.audio?.track?.translationID == "t2")
        #expect(vm.audioTranslationChoices.map(\.id) == ["t2", "t1"])
        vm.audio?.togglePlayPause()
        await vm.selectAudioTranslation("t1")
        #expect(vm.audio?.isPlaying == true)
        #expect(service.plays.last?.content == .speech(text: "[t1-1]", languageCode: "en"))
    }
}
