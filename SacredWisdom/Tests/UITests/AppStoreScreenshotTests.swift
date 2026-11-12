import XCTest

/// Generates App Store screenshots into AppStore/screenshots/. Skipped unless requested:
///   TEST_RUNNER_SW_APPSTORE_SCREENSHOTS=1 xcodebuild test -only-testing:SacredWisdomUITests/AppStoreScreenshotTests \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
/// Screens show real app states only: verified passages and no AI text (a scripted explanation would
/// misrepresent the product).
final class AppStoreScreenshotTests: XCTestCase {
    private static let output = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "AppStore/screenshots")

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SW_APPSTORE_SCREENSHOTS"] == "1",
                          "Set TEST_RUNNER_SW_APPSTORE_SCREENSHOTS=1 to generate App Store screenshots")
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
    }

    @MainActor
    private func save(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: Self.output.appending(path: "\(name).png"))
    }

    @MainActor
    private func capture(appearance: XCUIDevice.Appearance, suffix: String) {
        XCUIDevice.shared.appearance = appearance
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
        XCTAssertTrue(el("home.searchBar").waitForExistence(timeout: 5))
        sleep(1); save("01-home-\(suffix)")

        app.tabBars.firstMatch.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        field.tap(); field.typeText("merciful\n")
        XCTAssertTrue(el("searchResult.bible.matthew.5.7").waitForExistence(timeout: 5))
        el("searchResult.bookmark.quran.1.1").tap()
        sleep(1); save("02-search-\(suffix)")

        el("searchResult.bible.matthew.5.7").tap()
        XCTAssertTrue(el("screen.passageDetail").waitForExistence(timeout: 3))
        sleep(1); save("03-verse-details-\(suffix)")

        app.tabBars.firstMatch.buttons["Library"].tap()
        el("religionCard.islam").tap()
        el("religionLibrary.browse").tap()
        el("section.quran.surah1").tap()
        XCTAssertTrue(el("screen.reader").waitForExistence(timeout: 3))
        sleep(1); save("04-reader-\(suffix)")

        app.tabBars.firstMatch.buttons["Favorites"].tap()
        XCTAssertTrue(el("favorite.quran.1.1").waitForExistence(timeout: 5))
        sleep(1); save("05-favorites-\(suffix)")
        app.terminate()
        XCUIDevice.shared.appearance = .light
    }

    @MainActor func testLightScreenshots() { capture(appearance: .light, suffix: "light") }
    @MainActor func testDarkScreenshots() { capture(appearance: .dark, suffix: "dark") }
}
