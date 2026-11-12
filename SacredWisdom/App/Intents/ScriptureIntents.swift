import AppIntents
import Foundation

/// Searches local scripture and returns the relevant references (spoken), without opening the app.
struct SearchScriptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Scripture"
    static let description = IntentDescription("Searches all installed sacred texts and returns matching references.")

    @Parameter(title: "Search", requestValueDialog: "What would you like to search for?")
    var query: String

    static var parameterSummary: some ParameterSummary { Summary("Search scripture for \(\.$query)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[PassageEntity]> & ProvidesDialog {
        let response = try await AppSession.shared.intentService.searchReferences(query)
        return .result(value: await PassageEntity.entities(for: response.passages), dialog: "\(response.dialog)")
    }
}

/// Opens the app on the Search tab with results for the query (the interactive form of search).
struct OpenSearchResultsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Holy Books"
    static let description = IntentDescription("Opens Sacred Wisdom and shows search results across all traditions.")
    static let openAppWhenRun = true

    @Parameter(title: "Search", requestValueDialog: "What would you like to search for?")
    var query: String

    static var parameterSummary: some ParameterSummary { Summary("Show results for \(\.$query)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppSession.shared.coordinator.showSearchResults(for: query)
        return .result()
    }
}

/// Answers a spiritual question with relevant passages, quoted verbatim. No generated text (AI is Phase 7).
struct AskQuestionIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask a Question"
    static let description = IntentDescription("Finds passages from different traditions that speak to your question.")

    @Parameter(title: "Question", requestValueDialog: "What would you like to ask?")
    var question: String

    static var parameterSummary: some ParameterSummary { Summary("Ask \(\.$question)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[PassageEntity]> & ProvidesDialog {
        let response = try await AppSession.shared.intentService.answer(question)
        return .result(value: await PassageEntity.entities(for: response.passages), dialog: "\(response.dialog)")
    }
}

/// "Find verses about peace": a topic-based question usable directly in a Siri phrase.
struct FindVersesAboutTopicIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Verses About a Topic"
    static let description = IntentDescription("Finds passages from different traditions about a topic.")

    @Parameter(title: "Topic")
    var topic: ScriptureTopic

    static var parameterSummary: some ParameterSummary { Summary("Find verses about \(\.$topic)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[PassageEntity]> & ProvidesDialog {
        let response = try await AppSession.shared.intentService.answer(topic.query.query)
        return .result(value: await PassageEntity.entities(for: response.passages), dialog: "\(response.dialog)")
    }
}

/// Opens Verse Details for a passage.
struct OpenPassageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Passage"
    static let description = IntentDescription("Opens a scripture passage in Sacred Wisdom.")
    static let openAppWhenRun = true

    @Parameter(title: "Passage")
    var passage: PassageEntity

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$passage)") }

    init() {}

    init(passage: PassageEntity) {
        self.passage = passage
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppSession.shared.coordinator.openPassage(passage.id)
        return .result()
    }
}

/// Returns (speaks) today's passage.
struct DailyVerseIntent: AppIntent {
    static let title: LocalizedStringResource = "Today’s Passage"
    static let description = IntentDescription("Reads today’s passage, which rotates through all six traditions.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<PassageEntity?> & ProvidesDialog {
        let response = try await AppSession.shared.intentService.dailyPassage(on: Date())
        let entity = await PassageEntity.entities(for: response.passages).first
        return .result(value: entity, dialog: "\(response.dialog)")
    }
}

/// Opens today's passage in the app.
struct OpenDailyPassageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Daily Scripture"
    static let description = IntentDescription("Opens today’s passage in Sacred Wisdom.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let response = try await AppSession.shared.intentService.dailyPassage(on: Date())
        if let passage = response.passages.first {
            AppSession.shared.coordinator.openPassage(passage.id)
        } else {
            AppSession.shared.coordinator.select(.home)
        }
        return .result()
    }
}
