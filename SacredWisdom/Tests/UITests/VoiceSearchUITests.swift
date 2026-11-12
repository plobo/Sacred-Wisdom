import XCTest

/// In-app voice input, independent of Siri. Automation has no microphone, so the app is launched with a
/// scripted recognizer that "hears" a fixed phrase.
final class VoiceSearchUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        app.tabBars.firstMatch.buttons["Search"].tap()
        return app
    }

    @MainActor
    func testSpokenQueryRunsSearch() {
        let app = launch(["-ui-testing-speech", "still waters"])
        app.buttons["search.voice"].firstMatch.tap()
        // The scripted phrase finishes in well under a second, so the sheet may already be gone: check the outcome.
        let result = app.descendants(matching: .any)["searchResult.tanakh.psalms.23.2"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "still waters")
    }

    @MainActor
    func testDeniedPermissionExplainsAndCanBeDismissed() {
        let app = launch(["-ui-testing-speech-denied"])
        app.buttons["search.voice"].firstMatch.tap()
        let transcript = app.staticTexts["voice.transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 3))
        let predicate = NSPredicate(format: "label CONTAINS %@", "Allow microphone")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: transcript)], timeout: 3), .completed)
        app.buttons["voice.cancel"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["screen.voiceSearch"].waitForExistence(timeout: 1))
    }
}
