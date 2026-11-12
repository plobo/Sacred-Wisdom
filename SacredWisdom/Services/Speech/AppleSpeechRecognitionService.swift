import AVFoundation
import Foundation
import Speech

/// Live speech-to-text with the Speech framework. Recognition is forced on device, so audio never leaves
/// the phone and voice search works offline.
@MainActor
final class AppleSpeechRecognitionService: SpeechRecognitionService {
    static let maximumListeningTime: Duration = .seconds(60)

    private let audioEngine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func prepare() async -> SpeechAvailability {
        guard let recognizer, recognizer.supportsOnDeviceRecognition else { return .unsupported }
        let status = await Self.requestSpeechAuthorization()
        switch status {
        case .authorized: break
        case .restricted: return .restricted
        default: return .denied
        }
        guard await AVAudioApplication.requestRecordPermission() else { return .denied }
        return recognizer.isAvailable ? .available : .unsupported
    }

    func transcribe() async -> AsyncThrowingStream<SpeechTranscript, any Error> {
        let (stream, continuation) = AsyncThrowingStream<SpeechTranscript, any Error>.makeStream()
        do {
            try start(continuation)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.tearDown() }
            }
        } catch {
            tearDown()
            continuation.finish(throwing: error)
        }
        return stream
    }

    func stop() async {
        timeout?.cancel()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio() // the recognizer now delivers its final result
    }

    private func start(_ continuation: AsyncThrowingStream<SpeechTranscript, any Error>.Continuation) throws {
        guard let recognizer else { throw AppError.unexpected("No speech recognizer") }
        tearDown()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .search
        self.request = request

        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.tap(appendingTo: request))
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(continuation))
        timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.maximumListeningTime)
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    private func tearDown() {
        timeout?.cancel()
        task?.cancel()
        task = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Built outside the main actor: the audio tap and the result handler run on background threads.

    private nonisolated static func tap(appendingTo request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let request = request // appending buffers is thread-safe
        return { buffer, _ in request.append(buffer) }
    }

    private nonisolated static func resultHandler(
        _ continuation: AsyncThrowingStream<SpeechTranscript, any Error>.Continuation
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            if let result {
                continuation.yield(SpeechTranscript(text: result.bestTranscription.formattedString, isFinal: result.isFinal))
                if result.isFinal { continuation.finish() }
            } else if let error {
                continuation.finish(throwing: error)
            }
        }
    }

    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}
