import XCTest

/// Phase 8 acceptance. Packages are served from the repository's content/packages folder via file:// URLs,
/// which exercises the real URLSession download, verification and import without a server.
final class OfflineContentUITests: XCTestCase {
    private var app: XCUIApplication!

    private static let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private static let manifest = repo.appending(path: "content/packages/manifest.json").absoluteString
    private static let tampered = repo.appending(path: "SacredWisdom/Tests/Fixtures/tampered-packages/manifest.json").absoluteString

    override func setUp() async throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ arguments: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
    }

    @MainActor
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    @MainActor
    private func openOfflineContent() {
        app.tabBars.firstMatch.buttons["Settings"].tap()
        element("settings.offlineContent").tap()
        XCTAssertTrue(element("screen.offlineContent").waitForExistence(timeout: 3))
    }

    @MainActor
    private func firstGitaReference() -> String {
        app.tabBars.firstMatch.buttons["Library"].tap()
        let card = element("religionCard.hinduism")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        element("religionLibrary.browse").tap()
        let section = element("section.gita.ch2")
        XCTAssertTrue(section.waitForExistence(timeout: 3))
        section.tap()
        let reference = element("reader.reference")
        XCTAssertTrue(reference.waitForExistence(timeout: 3))
        return reference.label
    }

    @MainActor
    func testDownloadWorksOfflineAfterRelaunchAndRemovalRestoresSample() {
        launch(["-ui-testing-manifest-url", Self.manifest])
        openOfflineContent()
        let download = app.buttons["package.bhagavad-gita-ch2.download"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        download.tap()
        let status = element("package.bhagavad-gita-ch2.status")
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForLabel(status, containing: "Installed"), status.label)

        // Relaunch with no content server at all: the downloaded chapter must still be there.
        app.terminate()
        launch(["-ui-testing-keep-packages"])
        XCTAssertEqual(firstGitaReference(), "Bhagavad Gita 2.1")

        openOfflineContent()
        XCTAssertTrue(waitForLabel(element("offline.notice"), containing: "No content server"))
        let remove = app.buttons["package.bhagavad-gita-ch2.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.tap()
        app.buttons["offline.confirmRemove"].firstMatch.tap()
        XCTAssertFalse(element("package.bhagavad-gita-ch2").waitForExistence(timeout: 2))
        app.tabBars.firstMatch.buttons["Library"].tap()
        app.tabBars.firstMatch.buttons["Library"].tap() // pop to the root
        XCTAssertEqual(firstGitaReference(), "Bhagavad Gita 2.47")
    }

    @MainActor
    func testTamperedPackageIsRejected() {
        launch(["-ui-testing-manifest-url", Self.tampered])
        openOfflineContent()
        let download = app.buttons["package.dhammapada-ch1.download"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        download.tap()
        let status = element("package.dhammapada-ch1.status")
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForLabel(status, containing: "damaged"), status.label)
        XCTAssertTrue(app.buttons["package.dhammapada-ch1.download"].exists) // can retry; nothing installed
    }
}
