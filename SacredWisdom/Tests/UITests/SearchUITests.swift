import XCTest

final class SearchUITests: XCTestCase {
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
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    @MainActor
    private func search(_ text: String) {
        app.tabBars.firstMatch.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text + "\n")
    }

    @MainActor
    func testSearchOpensMatchingPassage() {
        search("peacemakers")
        let result = element("searchResult.bible.matthew.5.9")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(element("searchGroup.christianity").exists)
        result.tap()
        XCTAssertTrue(element("screen.passageDetail").waitForExistence(timeout: 3))
        XCTAssertEqual(element("detail.reference").label, "Matthew 5:9")
    }

    @MainActor
    func testQueryReachesAllSixTraditionsAndFilterNarrows() {
        search("the")
        for id in ["hinduism", "christianity", "islam", "judaism", "buddhism", "sikhism"] {
            XCTAssertTrue(element("searchGroup.\(id)").waitForExistence(timeout: 5), "missing group \(id)")
        }
        element("filter.religion.sikhism").tap()
        XCTAssertTrue(element("searchGroup.sikhism").waitForExistence(timeout: 3))
        XCTAssertFalse(element("searchGroup.christianity").exists)
    }

    @MainActor
    func testSubmittedQueryAppearsInRecentSearches() {
        search("shepherd")
        XCTAssertTrue(element("searchResult.tanakh.psalms.23.1").waitForExistence(timeout: 5))
        // Clearing the query returns to the idle screen, which lists recent searches.
        // (iOS 26 has no "Cancel" button on an always-visible search field.)
        app.searchFields.firstMatch.buttons["Clear text"].tap()
        XCTAssertTrue(element("recentSearch.shepherd").waitForExistence(timeout: 3))
    }

    @MainActor
    func testSuggestedQuestionRunsSearch() {
        app.tabBars.firstMatch.buttons["Search"].tap()
        let suggestion = element("suggestion.2") // "How can hatred cease?"
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        XCTAssertTrue(element("searchGroup.buddhism").waitForExistence(timeout: 5))
    }

    @MainActor
    func testHomeSearchBarOpensSearch() {
        let bar = element("home.searchBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.tap()
        XCTAssertTrue(element("screen.search").waitForExistence(timeout: 3))
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 3))
    }
}
