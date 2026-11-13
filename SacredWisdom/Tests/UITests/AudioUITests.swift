import XCTest

/// Listening (spec §11). UI tests use the scripted audio service: silent, about two seconds per passage.
final class AudioUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extra
        app.launch()
    }

    @MainActor
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ value: String, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format, value), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func openMatthew5() {
        app.tabBars.firstMatch.buttons["Library"].tap()
        let card = element("religionCard.christianity")
        var swipes = 0
        while !card.isHittable, swipes < 5 { app.swipeUp(); swipes += 1 }
        card.tap()
        element("religionLibrary.browse").tap()
        XCTAssertTrue(element("section.bible.matthew.5").waitForExistence(timeout: 3))
        element("section.bible.matthew.5").tap()
        XCTAssertTrue(element("screen.reader").waitForExistence(timeout: 3))
    }

    @MainActor
    func testReaderPlaysPausesAndContinuesToNextPassage() {
        launch()
        openMatthew5()
        let play = app.buttons["audio.playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 3))
        XCTAssertEqual(play.label, "Listen")
        XCTAssertTrue(element("audio.status").label.contains("system voice"), element("audio.status").label)

        play.tap()
        XCTAssertTrue(wait(play, "label == %@", "Pause"))
        play.tap()
        XCTAssertTrue(wait(play, "label == %@", "Resume"))
        XCTAssertTrue(element("audio.status").label.hasPrefix("Paused"))
        play.tap()
        XCTAssertTrue(wait(play, "label == %@", "Pause"))

        // The passage finishes; the reader moves on and keeps listening.
        let reference = element("reader.reference")
        XCTAssertTrue(wait(reference, "label == %@", "Matthew 5:4", timeout: 8), reference.label)
        XCTAssertTrue(wait(play, "label == %@", "Pause"))
    }

    @MainActor
    func testSpeedAndVoiceChoices() {
        launch()
        openMatthew5()
        let speed = app.buttons["audio.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 3))
        XCTAssertEqual(speed.value as? String, "1×")
        speed.tap()
        app.buttons["1.5×"].firstMatch.tap()
        XCTAssertTrue(wait(speed, "value == %@", "1.5×"))

        let voice = app.buttons["audio.voice"]
        XCTAssertTrue(voice.exists)
        voice.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rowan")).firstMatch.tap()
        XCTAssertTrue(wait(voice, "value BEGINSWITH %@", "Rowan"))

        // Speed is remembered app-wide (Settings shows it).
        app.tabBars.firstMatch.buttons["Settings"].tap()
        let setting = element("settings.playbackSpeed")
        XCTAssertTrue(setting.waitForExistence(timeout: 3))
        XCTAssertTrue(setting.label.contains("1.5×") || (setting.value as? String) == "1.5×",
                      "\(setting.label) \(String(describing: setting.value))")
        XCTAssertTrue(element("settings.continuousPlayback").exists)
    }

    @MainActor
    func testVerseDetailsListensAndChoosesTranslation() {
        launch()
        openMatthew5()
        app.buttons["reader.details"].firstMatch.tap()
        XCTAssertTrue(element("screen.passageDetail").waitForExistence(timeout: 3))
        let play = app.buttons["audio.playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 3))
        let translation = app.buttons["audio.translation"]
        XCTAssertTrue(translation.exists)
        let before = translation.value as? String ?? ""
        translation.tap()
        let other = before.contains("World English") ? "King James" : "World English"
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", other)).firstMatch.tap()
        XCTAssertTrue(wait(translation, "value CONTAINS %@", other))

        play.tap()
        XCTAssertTrue(wait(play, "label == %@", "Pause"))
        XCTAssertTrue(element("audio.status").label.contains(other), element("audio.status").label)

        // Leaving the screen stops listening.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("screen.reader").waitForExistence(timeout: 3))
        XCTAssertTrue(wait(app.buttons["audio.playPause"], "label == %@", "Listen"))
    }

    @MainActor
    func testNoVoiceExplainsWhy() {
        launch(["-ui-testing-audio-no-voice"])
        openMatthew5()
        let reason = element("audio.unavailable")
        XCTAssertTrue(reason.waitForExistence(timeout: 3))
        XCTAssertTrue(reason.label.contains("No voice is installed"), reason.label)
        XCTAssertFalse(app.buttons["audio.playPause"].exists)
    }
}
