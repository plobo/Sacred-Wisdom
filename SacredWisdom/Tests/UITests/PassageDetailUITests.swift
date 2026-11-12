import XCTest

/// Phase 5 acceptance: search results open the correct passage, related passages open their own details,
/// bookmarks and notes persist after an app restart.
final class PassageDetailUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(store: String? = nil, reset: Bool = false) {
        app = XCUIApplication()
        var arguments = ["-ui-testing"]
        if let store { arguments += ["-ui-testing-user-data-store", store] }
        if reset { arguments.append("-ui-testing-reset-user-data") }
        app.launchArguments = arguments
        app.launch()
    }

    @MainActor
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    /// Scrolls until the element is on screen and clear of the floating tab bar.
    @MainActor
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(element)", file: file, line: line)
        let tabBarTop = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
        var swipes = 0
        while (!element.isHittable || element.frame.maxY > tabBarTop - 8), swipes < 8 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    @MainActor
    private func search(_ text: String) {
        app.tabBars.firstMatch.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text + "\n")
    }

    @MainActor
    private func openFromSearch(_ query: String, passageID: String) {
        search(query)
        let result = element("searchResult.\(passageID)")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(element("screen.passageDetail").waitForExistence(timeout: 3))
    }

    @MainActor
    func testSearchResultOpensDetailsWithTextAttributionAndContext() {
        launch()
        openFromSearch("peacemakers", passageID: "bible.matthew.5.9")
        XCTAssertEqual(element("detail.reference").label, "Matthew 5:9")
        XCTAssertTrue(element("detail.translation.bible-kjv").label
            .hasPrefix("Blessed are the peacemakers: for they shall be called the children of God."))
        XCTAssertTrue(element("detail.translation.bible-web").exists)
        XCTAssertTrue(element("detail.attribution").label.contains("King James Version"))
        XCTAssertTrue(app.buttons["detail.share"].firstMatch.exists)

        let readInContext = element("detail.readInContext")
        reveal(readInContext)
        readInContext.tap()
        XCTAssertTrue(element("screen.reader").waitForExistence(timeout: 3))
        XCTAssertEqual(element("reader.reference").label, "Matthew 5:9")
    }

    @MainActor
    func testRelatedPassageOpensItsOwnDetails() {
        launch()
        openFromSearch("merciful", passageID: "bible.matthew.5.7")
        let related = element("relatedPassage.quran.1.1")
        reveal(related)
        XCTAssertTrue(related.label.contains("Mercy"), related.label)
        related.tap()
        XCTAssertTrue(element("detail.reference").waitForExistence(timeout: 3))
        let reference = app.staticTexts.matching(identifier: "detail.reference").element(boundBy: 0)
        let predicate = NSPredicate(format: "label == %@", "Al-Fatihah 1:1")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: reference)], timeout: 3), .completed)
        XCTAssertTrue(element("detail.originalText").exists)
    }

    @MainActor
    func testBookmarkAndNotePersistAfterRestart() {
        let store = "phase5-persistence"
        launch(store: store, reset: true)
        openFromSearch("shepherd", passageID: "tanakh.psalms.23.1")
        app.buttons["detail.bookmark"].firstMatch.tap()
        XCTAssertTrue(element("detail.collectionMenu").waitForExistence(timeout: 3))

        let editNote = element("detail.editNote")
        reveal(editNote)
        editNote.tap()
        let editor = element("noteEditor.text")
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Read alongside Al-Fatihah 1:6")
        app.buttons["noteEditor.save"].firstMatch.tap()
        XCTAssertTrue(element("detail.noteText").waitForExistence(timeout: 3))

        app.terminate()
        launch(store: store)

        app.tabBars.firstMatch.buttons["Favorites"].tap()
        let saved = element("favorite.tanakh.psalms.23.1")
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.label.contains("Read alongside Al-Fatihah 1:6"), saved.label)
        saved.tap()
        XCTAssertTrue(element("detail.noteText").waitForExistence(timeout: 3))
        XCTAssertEqual(element("detail.noteText").label, "Read alongside Al-Fatihah 1:6")
        XCTAssertEqual(app.buttons["detail.bookmark"].firstMatch.label, "Remove Bookmark")
    }

    @MainActor
    func testSearchResultBookmarkAppearsInFavoritesAndCanBeRemoved() {
        launch()
        search("still waters")
        let bookmark = element("searchResult.bookmark.tanakh.psalms.23.2")
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        bookmark.tap()

        app.tabBars.firstMatch.buttons["Favorites"].tap()
        let saved = element("favorite.tanakh.psalms.23.2")
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.swipeLeft()
        app.buttons["Remove"].firstMatch.tap()
        XCTAssertTrue(element("state.empty").waitForExistence(timeout: 3))
    }

    @MainActor
    func testReaderViewsAppearInRecentlyViewedAndDetailsOpenFromReader() {
        launch()
        let daily = element("home.dailyPassage.open")
        reveal(daily)
        daily.tap()
        XCTAssertTrue(element("screen.reader").waitForExistence(timeout: 3))
        let reference = element("reader.reference").label

        app.buttons["reader.details"].firstMatch.tap()
        XCTAssertTrue(element("screen.passageDetail").waitForExistence(timeout: 3))
        XCTAssertEqual(element("detail.reference").label, reference)

        app.tabBars.firstMatch.buttons["Home"].tap()
        app.tabBars.firstMatch.buttons["Home"].tap() // second tap pops to the root
        let recent = element("home.recent")
        reveal(recent)
        XCTAssertTrue(recent.staticTexts[reference].waitForExistence(timeout: 3), "recently viewed should list \(reference)")
    }
}
