import Foundation

enum SpeechAvailability: Equatable, Sendable {
    case available
    /// The user declined speech recognition or microphone access.
    case denied
    /// Parental controls or device management prevent it.
    case restricted
    /// No on-device recognizer for the current language (voice input never leaves the device).
    case unsupported

    var userMessage: String {
        switch self {
        case .available: ""
        case .denied: String(localized: "Allow microphone and speech recognition in Settings to search by voice.")
        case .restricted: String(localized: "Voice input is restricted on this device.")
        case .unsupported: String(localized: "On-device voice input isn’t available for your language on this device.")
        }
    }
}

struct SpeechTranscript: Equatable, Sendable {
    let text: String
    let isFinal: Bool
}

/// In-app speech-to-text for voice search. Separate from Siri: Siri invokes App Intents; this only fills
/// the search field. Implementations must recognize on device.
protocol SpeechRecognitionService: Sendable {
    /// Asks for permission when needed and reports whether listening can start.
    func prepare() async -> SpeechAvailability
    /// Starts listening. Yields partial transcripts and finishes after the final one.
    func transcribe() async -> AsyncThrowingStream<SpeechTranscript, any Error>
    /// Stops listening; the stream then delivers its final transcript and finishes.
    func stop() async
}

/// Plays back a fixed transcript word by word. Used by UI tests (no microphone in automation) and unit tests.
actor ScriptedSpeechRecognitionService: SpeechRecognitionService {
    private let availability: SpeechAvailability
    private let words: [String]
    private let wordDelay: Duration
    private var continuation: AsyncThrowingStream<SpeechTranscript, any Error>.Continuation?
    private var spoken: [String] = []
    private var playback: Task<Void, Never>?

    init(transcript: String, availability: SpeechAvailability = .available, wordDelay: Duration = .milliseconds(150)) {
        self.words = transcript.split(separator: " ").map(String.init)
        self.availability = availability
        self.wordDelay = wordDelay
    }

    func prepare() -> SpeechAvailability { availability }

    func transcribe() -> AsyncThrowingStream<SpeechTranscript, any Error> {
        let (stream, continuation) = AsyncThrowingStream<SpeechTranscript, any Error>.makeStream()
        self.continuation = continuation
        spoken = []
        playback = Task { await self.play() }
        return stream
    }

    func stop() {
        playback?.cancel()
        finish()
    }

    private func play() async {
        for word in words {
            try? await Task.sleep(for: wordDelay)
            guard !Task.isCancelled, continuation != nil else { return }
            spoken.append(word)
            continuation?.yield(SpeechTranscript(text: spoken.joined(separator: " "), isFinal: false))
        }
        finish()
    }

    private func finish() {
        guard let continuation else { return }
        continuation.yield(SpeechTranscript(text: spoken.joined(separator: " "), isFinal: true))
        continuation.finish()
        self.continuation = nil
    }
}
