import Foundation
import Testing
@testable import SacredWisdom

/// Spy that records whether the AI was asked anything.
actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

struct SpyAIService: ScriptureAIService {
    let base: any ScriptureAIService
    let calls = CallCounter()
    var providerName: String { base.providerName }
    func availability() async -> AIAvailability { await base.availability() }
    func answer(question: String, passages: [ScripturePassage]) async throws(AppError) -> ScriptureAIResponse {
        await calls.increment()
        return try await base.answer(question: question, passages: passages)
    }
}

struct ThrowingAIService: ScriptureAIService {
    let providerName = "Broken"
    func availability() async -> AIAvailability { .available }
    func answer(question: String, passages: [ScripturePassage]) async throws(AppError) -> ScriptureAIResponse {
        throw .unexpected("model crashed")
    }
}

@Suite struct AskQuestionIntegrationTests {
    private func searchUseCase() throws -> SearchScriptureUseCase {
        let url = try #require(Bundle(for: AppDependencies.self)
            .url(forResource: SampleLibraryRepository.resourceName, withExtension: "json"))
        let database = DatabaseManager(location: .inMemory,
                                       bundledPackages: [.init(id: SampleLibraryRepository.resourceName, url: url)])
        let sqlite = SQLiteScriptureRepository(database: database)
        return SearchScriptureUseCase(
            search: LocalKeywordSearchRepository(index: FullTextSearchIndex(database: database), scripture: sqlite),
            religions: sqlite
        )
    }

    private func useCase(_ ai: any ScriptureAIService, enabled: Bool = true) throws -> AnswerQuestionUseCase {
        AnswerQuestionUseCase(search: try searchUseCase(), ai: ai, preferences: InMemoryAIPreferenceStore(enabled: enabled))
    }

    private let grounded = ScriptedScriptureAIService(
        explanation: "Passage [1] blesses the merciful. Passage [2] calls God the Merciful. It also says “mercy for every creature” [2].",
        citedPassageNumbers: [1, 2]
    )

    @Test func explanationCitesRetrievedPassagesAndDropsFabricatedQuote() async throws {
        let answer = try await useCase(grounded).execute("What is said about the merciful?")
        guard case .explanation(let explanation) = answer.explanation else { Issue.record("\(answer.explanation)"); return }
        #expect(explanation.removedSentenceCount == 1)
        #expect(!explanation.text.contains("every creature"))
        let contextIDs = Set(answer.contextPassages.map(\.id))
        #expect(explanation.citations.allSatisfy { contextIDs.contains($0.passageID) })
        #expect(explanation.citations.count == 2)
    }

    @Test func contextInterleavesTraditionsBestFirst() async throws {
        let answer = try await useCase(grounded).execute("What is said about the merciful?")
        let traditions = answer.contextPassages.map(\.religionID)
        #expect(Set(traditions.prefix(2)) == ["christianity", "islam"]) // one from each before any second
        #expect(answer.contextPassages.count == 3)
    }

    @Test func aiIsOptionalAndPassagesAreUnaffected() async throws {
        let question = "How can hatred cease?"
        let withAI = try await useCase(grounded).execute(question)
        let disabled = try await useCase(grounded, enabled: false).execute(question)
        let unavailable = try await useCase(UnavailableScriptureAIService(reason: "No model")).execute(question)
        let broken = try await useCase(ThrowingAIService()).execute(question)

        #expect(disabled.explanation == .disabled)
        #expect(unavailable.explanation == .unavailable(reason: "No model"))
        guard case .failed = broken.explanation else { Issue.record("expected failure"); return }
        for answer in [disabled, unavailable, broken] {
            #expect(answer.results == withAI.results)
            #expect(!answer.results.isEmpty)
        }
    }

    @Test func unverifiableExplanationIsWithheld() async throws {
        let fabricated = ScriptedScriptureAIService(explanation: "As John 3:16 says, “God so loved the world” [1].", citedPassageNumbers: [1])
        let answer = try await useCase(fabricated).execute("What is said about the merciful?")
        guard case .failed(let message) = answer.explanation else { Issue.record("\(answer.explanation)"); return }
        #expect(message.contains("withheld"))
    }

    @Test func noPassagesMeansTheAIIsNeverAsked() async throws {
        let spy = SpyAIService(base: grounded)
        let answer = try await useCase(spy).execute("forgiveness")
        #expect(answer.results.isEmpty)
        #expect(answer.explanation == .notAttempted)
        #expect(await spy.calls.count == 0)
    }

    /// Runs Apple's model for real when this machine has it; otherwise checks the fallback message.
    @Test func liveFoundationModelsOutputIsAlwaysValidated() async throws {
        let url = try #require(Bundle(for: AppDependencies.self)
            .url(forResource: SampleLibraryRepository.resourceName, withExtension: "json"))
        let repo = SQLiteScriptureRepository(database: DatabaseManager(
            location: .inMemory, bundledPackages: [.init(id: SampleLibraryRepository.resourceName, url: url)]))
        let live = FoundationModelsScriptureAIService(religions: repo)
        let availability = await live.availability()
        print("Foundation Models availability: \(availability)")
        let answer = try await useCase(live).execute("What is said about peace?")
        switch (availability, answer.explanation) {
        case (.unavailable(let reason), let outcome):
            #expect(outcome == .unavailable(reason: reason))
        case (.available, .explanation(let explanation)):
            print("Validated explanation: \(explanation.text) cites \(explanation.citations.map(\.reference))")
            let contextIDs = Set(answer.contextPassages.map(\.id))
            #expect(!explanation.citations.isEmpty && explanation.citations.allSatisfy { contextIDs.contains($0.passageID) })
            let revalidated = AIResponseValidator.validate(
                ScriptureAIResponse(explanation: explanation.text, citedPassageNumbers: explanation.citations.map(\.number),
                                    providerName: ""), passages: answer.contextPassages)
            #expect((try? revalidated.get().removedSentenceCount) == 0)
        case (.available, let outcome):
            print("Live model produced no verifiable explanation: \(outcome)")
            guard case .failed = outcome else { Issue.record("unexpected \(outcome)"); return }
        }
    }
}

@MainActor
@Suite struct AskQuestionViewModelTests {
    struct StubAnswer: AnswerQuestionUseCaseProtocol {
        var error: AppError?
        func execute(_ question: String) async throws(AppError) -> QuestionAnswer {
            if let error { throw error }
            return QuestionAnswer(id: UUID(), question: question,
                                  results: SearchResults(query: SearchQueryParser.parse(question), groups: []),
                                  contextPassages: [], explanation: .notAttempted)
        }
    }

    @Test func sendTrimsAppendsAndClearsDraft() async {
        let vm = AskQuestionViewModel(answerQuestion: StubAnswer())
        #expect(!vm.canSend)
        vm.draft = "  What is said about peace?  "
        #expect(vm.canSend)
        await vm.send()
        #expect(vm.draft.isEmpty)
        #expect(vm.exchanges.map(\.question) == ["What is said about peace?"])
        guard case .answered = vm.exchanges[0].status else { Issue.record("not answered"); return }
    }

    @Test func searchFailureShowsErrorAndRetryReplacesIt() async {
        let vm = AskQuestionViewModel(answerQuestion: StubAnswer(error: .database("closed")))
        await vm.ask("peace")
        #expect(vm.exchanges.first?.status == .failed(AppError.database("").userMessage))
        await vm.retry(vm.exchanges[0])
        #expect(vm.exchanges.count == 1)
        vm.clear()
        #expect(vm.exchanges.isEmpty)
    }

    @Test func longQuestionsAreCapped() async {
        let vm = AskQuestionViewModel(answerQuestion: StubAnswer())
        vm.draft = String(repeating: "a", count: 1_000)
        await vm.send()
        #expect(vm.exchanges[0].question.count == AskQuestionViewModel.maximumQuestionLength)
    }

    @Test func settingsToggleIsRememberedAndAvailabilityExplained() async throws {
        let store = InMemoryAIPreferenceStore()
        let vm = SettingsViewModel(userData: try Fixtures.userData(), aiPreferences: store,
                                   ai: UnavailableScriptureAIService(reason: "Needs iOS 26."))
        await vm.load()
        #expect(vm.isAIEnabled)
        #expect(vm.aiStatusText == "Needs iOS 26.")
        await vm.setAIEnabled(false)
        #expect(await store.isEnabled() == false)
    }

    @Test func userDefaultsPreferenceDefaultsToOn() async throws {
        let defaults = try #require(UserDefaults(suiteName: "ai-pref-\(UUID().uuidString)"))
        let store = UserDefaultsAIPreferenceStore(defaults: defaults)
        #expect(await store.isEnabled())
        await store.setEnabled(false)
        #expect(await store.isEnabled() == false)
    }
}
