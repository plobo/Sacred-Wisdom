import XCTest

final class NavigationUITests: XCTestCase {
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
    func testHomeShowsSixTraditions() {
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 5) || app.scrollViews["screen.home"].exists)
        for id in ["hinduism", "christianity", "islam", "judaism", "buddhism", "sikhism"] {
            let card = app.descendants(matching: .any)["religionCard.\(id)"]
            card.scrollIntoViewIfNeeded(in: app)
            XCTAssertTrue(card.waitForExistence(timeout: 3), "Missing card for \(id)")
        }
    }

    @MainActor
    func testTabNavigation() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        let expectations: [(String, String)] = [
            ("Search", "screen.search"),
            ("Favorites", "screen.favorites"),
            ("Library", "screen.library"),
            ("Settings", "screen.settings"),
            ("Home", "screen.home"),
        ]
        for (tab, screen) in expectations {
            tabBar.buttons[tab].tap()
            XCTAssertTrue(app.descendants(matching: .any)[screen].waitForExistence(timeout: 3), "\(screen) not shown")
        }
    }

    @MainActor
    func testReligionCardOpensLibraryScreen() {
        let card = app.descendants(matching: .any)["religionCard.islam"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.religionLibrary"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Islam"].exists)
    }

}

private extension XCUIElement {
    @MainActor
    func scrollIntoViewIfNeeded(in app: XCUIApplication, maxSwipes: Int = 5) {
        var swipes = 0
        while !exists || !isHittable, swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }
}
