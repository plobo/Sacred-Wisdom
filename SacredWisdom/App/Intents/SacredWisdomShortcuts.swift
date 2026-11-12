import AppIntents

/// Siri phrases. Every phrase must contain the app name; free-text parameters cannot appear in phrases,
/// so Siri asks for the question or search after the phrase.
struct SacredWisdomShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskQuestionIntent(),
            phrases: ["Ask \(.applicationName)", "Ask \(.applicationName) a question"],
            shortTitle: "Ask Sacred Wisdom",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
        AppShortcut(
            intent: OpenSearchResultsIntent(),
            phrases: ["Search holy books in \(.applicationName)", "Search \(.applicationName)"],
            shortTitle: "Search Holy Books",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenDailyPassageIntent(),
            phrases: ["Open daily scripture in \(.applicationName)", "Open today’s passage in \(.applicationName)"],
            shortTitle: "Open Daily Scripture",
            systemImageName: "sun.horizon"
        )
        AppShortcut(
            intent: DailyVerseIntent(),
            phrases: ["What is today’s passage in \(.applicationName)", "Read today’s passage from \(.applicationName)"],
            shortTitle: "Today’s Passage",
            systemImageName: "text.quote"
        )
        AppShortcut(
            intent: FindVersesAboutTopicIntent(),
            phrases: [
                "Find verses about \(\.$topic) in \(.applicationName)",
                "Ask \(.applicationName) about \(\.$topic)",
            ],
            shortTitle: "Find Verses About Peace",
            systemImageName: "leaf"
        )
    }
}
