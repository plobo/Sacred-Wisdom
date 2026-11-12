import XCTest

/// Phase 7 acceptance on screen. The scripted model's reply cites [1] and includes a sentence quoting words
/// found in no passage; that sentence must never be displayed.
final class AskQuestionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(scriptedAI: Bool) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + (scriptedAI ? ["-ui-testing-ai-scripted"] : [])
        app.launch()
    }

    @MainActor
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    @MainActor
    private func openAsk() {
        let card = element("home.askQuestion")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        var swipes = 0
        let tabBarTop = app.tabBars.firstMatch.frame.minY
        while (!card.isHittable || card.frame.maxY > tabBarTop - 8), swipes < 6 { app.swipeUp(velocity: .slow); swipes += 1 }
        card.tap()
        XCTAssertTrue(element("ask.input").waitForExistence(timeout: 3))
    }

    @MainActor
    func testExplanationIsLabeledCitesPassagesAndOmitsFabricatedQuote() {
        launch(scriptedAI: true)
        openAsk()
        element("ask.suggestion.0").tap() // "What is said about peace?"

        let label = element("ask.aiLabel")
        XCTAssertTrue(label.waitForExistence(timeout: 8))
        XCTAssertTrue(label.label.contains("AI-generated explanation"), label.label)
        let explanation = element("ask.aiExplanation")
        XCTAssertTrue(explanation.label.contains("[1]"), explanation.label)
        XCTAssertFalse(explanation.label.contains("love conquers"), "fabricated quotation was displayed")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "love conquers")).firstMatch.exists)
        XCTAssertTrue(element("ask.aiRemoved").exists)
        XCTAssertTrue(element("ask.citation.1").exists)

        let view = element("ask.viewPassage.bible.matthew.5.9")
        var swipes = 0
        while !view.isHittable, swipes < 8 { app.swipeUp(velocity: .slow); swipes += 1 }
        view.tap()
        XCTAssertTrue(element("screen.passageDetail").waitForExistence(timeout: 3))
        XCTAssertEqual(element("detail.reference").label, "Matthew 5:9")
    }

    @MainActor
    func testWithoutAIPassagesStillAnswerTheQuestion() {
        launch(scriptedAI: false)
        openAsk()
        let input = element("ask.input")
        input.tap()
        input.typeText("Where is comfort found?")
        app.buttons["ask.send"].tap()

        let note = element("ask.aiNote")
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        XCTAssertTrue(note.label.contains("Showing passages only"), note.label)
        XCTAssertFalse(element("ask.aiLabel").exists)
        XCTAssertTrue(element("ask.passage.tanakh.psalms.23.4").exists)
        XCTAssertTrue(element("ask.passage.bible.matthew.5.4").exists)
    }

    @MainActor
    func testTurningAIOffInSettingsKeepsPassages() {
        launch(scriptedAI: true)
        app.tabBars.firstMatch.buttons["Settings"].tap()
        let toggle = app.switches["settings.aiToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        if toggle.value as? String == "1" { toggle.switches.firstMatch.tap() }
        XCTAssertEqual(toggle.value as? String, "0")

        app.tabBars.firstMatch.buttons["Home"].tap()
        openAsk()
        element("ask.suggestion.0").tap()
        let note = element("ask.aiNote")
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        XCTAssertTrue(note.label.contains("AI explanations are off"), note.label)
        XCTAssertTrue(element("ask.passage.bible.matthew.5.9").exists)
    }
}
