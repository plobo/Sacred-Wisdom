import XCTest

final class ReaderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = await MainActor.run {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launch()
            return app
        }
    }

    @MainActor
    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 3) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func openReader(religion: String, section: String) {
        app.tabBars.firstMatch.buttons["Library"].tap()
        let card = element("religionCard.\(religion)")
        var swipes = 0
        while !card.isHittable, swipes < 5 { app.swipeUp(); swipes += 1 }
        card.tap()
        element("religionLibrary.browse").tap()
        XCTAssertTrue(element("section.\(section)").waitForExistence(timeout: 3))
        element("section.\(section)").tap()
        XCTAssertTrue(element("screen.reader").waitForExistence(timeout: 3))
    }

    @MainActor
    func testBrowseQuranAndNavigatePassages() {
        openReader(religion: "islam", section: "quran.surah1")
        let reference = element("reader.reference")
        XCTAssertEqual(reference.label, "Al-Fatihah 1:1")
        XCTAssertTrue(element("reader.originalText").exists)
        XCTAssertTrue(element("reader.translationText").exists)
        XCTAssertFalse(element("reader.previous").isEnabled)

        element("reader.next").tap()
        XCTAssertTrue(waitForLabel(reference, "Al-Fatihah 1:2"))
        XCTAssertTrue(element("reader.previous").isEnabled)
        element("reader.previous").tap()
        XCTAssertTrue(waitForLabel(reference, "Al-Fatihah 1:1"))
    }

    @MainActor
    func testBibleTranslationSelection() {
        openReader(religion: "christianity", section: "bible.matthew.5")
        let text = element("reader.translationText")
        XCTAssertTrue(text.label.hasPrefix("Blessed are the poor in spirit: for theirs"), text.label)

        app.buttons["reader.translationMenu"].firstMatch.tap()
        app.buttons["World English Bible"].tap()
        XCTAssertTrue(app.staticTexts["“Blessed are the poor in spirit, for theirs is the Kingdom of Heaven."].waitForExistence(timeout: 3))
    }

    @MainActor
    func testDailyPassageOpensReader() {
        let daily = element("home.dailyPassage.open")
        XCTAssertTrue(daily.waitForExistence(timeout: 5))
        // The floating tab bar overlaps content, so scroll until the card clears it.
        let tabBarTop = app.tabBars.firstMatch.frame.minY
        var swipes = 0
        while (!daily.isHittable || daily.frame.maxY > tabBarTop), swipes < 5 { app.swipeUp(); swipes += 1 }
        daily.tap()
        XCTAssertTrue(element("screen.reader").waitForExistence(timeout: 3))
    }
}
