import Foundation
import Testing
@testable import SacredWisdom

@MainActor
@Suite struct IntentNavigationTests {
    @Test func openPassageShowsDetailsOnHome() {
        let coordinator = AppCoordinator()
        coordinator.push(.collection("bible"), in: .home)
        coordinator.select(.settings)
        coordinator.openPassage("quran.1.1")
        #expect(coordinator.selectedTab == .home)
        #expect(coordinator.paths[.home] == [.passageDetail("quran.1.1")])
    }

    @Test func showSearchResultsQueuesOneRequestUntilConsumed() throws {
        let coordinator = AppCoordinator()
        coordinator.push(.passageDetail("x"), in: .search)
        coordinator.showSearchResults(for: "peace")
        #expect(coordinator.selectedTab == .search)
        #expect(coordinator.paths[.search] == [])
        let request = try #require(coordinator.pendingSearch)
        #expect(request.query == "peace")

        coordinator.consumePendingSearch(UUID()) // a stale ID is ignored
        #expect(coordinator.pendingSearch == request)
        coordinator.consumePendingSearch(request.id)
        #expect(coordinator.pendingSearch == nil)
    }

    /// Runs the real intents against the app session (the test host's live library).
    @Test func openPassageIntentNavigatesTheSharedCoordinator() async throws {
        let entity = try #require(try await PassageEntityQuery().entities(for: ["bible.matthew.5.9"]).first)
        #expect(entity.reference == "Matthew 5:9")
        #expect(entity.collectionName == "Bible")
        _ = try await OpenPassageIntent(passage: entity).perform()
        #expect(AppSession.shared.coordinator.paths[.home] == [.passageDetail("bible.matthew.5.9")])
        #expect(AppSession.shared.coordinator.selectedTab == .home)
    }

    @Test func openSearchResultsIntentQueuesTheQuery() async throws {
        let intent = OpenSearchResultsIntent()
        intent.query = "still waters"
        _ = try await intent.perform()
        #expect(AppSession.shared.coordinator.selectedTab == .search)
        #expect(AppSession.shared.coordinator.pendingSearch?.query == "still waters")
        AppSession.shared.coordinator.consumePendingSearch(try #require(AppSession.shared.coordinator.pendingSearch).id)
    }

    @Test func entityQueryResolvesSpokenTextAndUnknownIDs() async throws {
        let query = PassageEntityQuery()
        #expect(try await query.entities(matching: "shepherd").map(\.id).contains("tanakh.psalms.23.1"))
        #expect(try await query.entities(for: ["no-such-passage"]).isEmpty)
        #expect(try await query.suggestedEntities().count == 1)
    }

    @Test func returningIntentsRunWithoutOpeningTheApp() async throws {
        #expect(!SearchScriptureIntent.openAppWhenRun)
        #expect(!AskQuestionIntent.openAppWhenRun)
        #expect(!DailyVerseIntent.openAppWhenRun)
        #expect(OpenPassageIntent.openAppWhenRun && OpenSearchResultsIntent.openAppWhenRun && OpenDailyPassageIntent.openAppWhenRun)
        let search = SearchScriptureIntent()
        search.query = "peacemakers"
        _ = try await search.perform()
        let ask = AskQuestionIntent()
        ask.question = "What is said about peace?"
        _ = try await ask.perform()
        _ = try await DailyVerseIntent().perform()
    }

    @Test func everySiriTopicHasASearchQuery() {
        #expect(ScriptureTopic.allCases.map(\.rawValue) == ScriptureTopicQuery.allCases.map(\.rawValue))
        #expect(ScriptureTopic.allCases.allSatisfy { ScriptureTopic.caseDisplayRepresentations[$0] != nil })
        #expect(ScriptureTopic.guidance.query.query == "path")
    }
}

@MainActor
@Suite struct VoiceSearchViewModelTests {
    @Test func listensAndFinishesWithTheFullTranscript() async {
        let vm = VoiceSearchViewModel(service: ScriptedSpeechRecognitionService(transcript: "still waters", wordDelay: .milliseconds(5)))
        await vm.start()
        #expect(vm.state == .finished("still waters"))
    }

    @Test func stoppingEarlyKeepsWhatWasHeard() async throws {
        let service = ScriptedSpeechRecognitionService(transcript: "the lord is my shepherd", wordDelay: .milliseconds(80))
        let vm = VoiceSearchViewModel(service: service)
        let listening = Task { await vm.start() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.isListening)
        await vm.stop()
        await listening.value
        guard case .finished(let text) = vm.state else { Issue.record("not finished: \(vm.state)"); return }
        #expect(!text.isEmpty)
        #expect("the lord is my shepherd".hasPrefix(text))
    }

    @Test(arguments: [SpeechAvailability.denied, .restricted, .unsupported])
    func unavailableRecognitionExplainsWhy(availability: SpeechAvailability) async {
        let vm = VoiceSearchViewModel(service: ScriptedSpeechRecognitionService(transcript: "x", availability: availability))
        await vm.start()
        #expect(vm.state == .failed(availability.userMessage))
    }

    @Test func silenceAsksToTryAgain() async {
        let vm = VoiceSearchViewModel(service: ScriptedSpeechRecognitionService(transcript: "", wordDelay: .milliseconds(1)))
        await vm.start()
        #expect(vm.state == .failed("I didn’t catch that. Please try again."))
    }

    @Test func cancelReturnsToIdleWithoutAResult() async throws {
        let vm = VoiceSearchViewModel(service: ScriptedSpeechRecognitionService(transcript: "a b c d e f", wordDelay: .milliseconds(50)))
        let listening = Task { await vm.start() }
        try await Task.sleep(for: .milliseconds(80))
        await vm.cancel()
        await listening.value
        #expect(vm.state == .idle)
    }

    @Test func uiTestingNeverUsesTheRealMicrophone() {
        #expect(AppConfiguration.scriptedSpeech(arguments: ["app"], isUITesting: false) == nil)
        #expect(AppConfiguration.scriptedSpeech(arguments: ["app", "-ui-testing"], isUITesting: true)?.availability == .unsupported)
        #expect(AppConfiguration.scriptedSpeech(arguments: ["app", "-ui-testing-speech", "still waters"], isUITesting: true)
            == .init(transcript: "still waters", availability: .available))
        #expect(AppConfiguration.scriptedSpeech(arguments: ["app", "-ui-testing-speech-denied"], isUITesting: true)?.availability == .denied)
    }
}
