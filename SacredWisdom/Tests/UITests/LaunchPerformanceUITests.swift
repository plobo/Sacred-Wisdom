import XCTest

/// Cold-launch time to first frame, as measured by XCTest (the splash is skipped under UI testing).
final class LaunchPerformanceUITests: XCTestCase {
    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()], options: {
            let options = XCTMeasureOptions()
            options.iterationCount = 3
            return options
        }()) {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launch()
        }
    }
}
