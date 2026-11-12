import Foundation
import Observation

/// In-app voice input for search. Independent of Siri.
@Observable
@MainActor
final class VoiceSearchViewModel: Identifiable {
    enum State: Equatable {
        case idle
        case preparing
        case listening(String)
        case finished(String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private let service: any SpeechRecognitionService

    init(service: any SpeechRecognitionService) {
        self.service = service
    }

    var transcript: String {
        switch state {
        case .listening(let text), .finished(let text): text
        default: ""
        }
    }

    var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    /// Listens until the recognizer delivers its final transcript (after `stop()` or a natural end).
    func start() async {
        switch state {
        case .preparing, .listening: return
        default: break
        }
        state = .preparing
        let availability = await service.prepare()
        guard availability == .available else {
            state = .failed(availability.userMessage)
            return
        }
        state = .listening("")
        var latest = ""
        do {
            for try await transcript in await service.transcribe() {
                latest = transcript.text
                if case .listening = state { state = .listening(latest) }
                if transcript.isFinal { break }
            }
        } catch {
            Log.speech.error("Recognition ended with an error: \(String(describing: error), privacy: .public)")
            guard case .listening = state else { return }
            state = latest.isEmpty ? .failed(String(localized: "Voice input stopped. Please try again.")) : .finished(latest)
            return
        }
        guard case .listening = state else { return } // cancelled meanwhile
        let final = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        state = final.isEmpty ? .failed(String(localized: "I didn’t catch that. Please try again.")) : .finished(final)
    }

    func stop() async {
        await service.stop()
    }

    func cancel() async {
        state = .idle
        await service.stop()
    }

    func reset() {
        state = .idle
    }
}
