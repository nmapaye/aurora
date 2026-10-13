import XCTest

/// Screenshots of the cutoff scenario card from the Design Gallery's
/// synthetic fixtures, for visual review. Appearance comes from the
/// simulator (`simctl ui … appearance`); text size from launch arguments.
/// Reminder saves in the gallery use a stub that never reaches notifications.
final class CutoffGalleryCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = true }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways
        add(shot)
    }

    private static let fixtures = ["Empty inputs", "Time ahead", "Invalid inputs", "Sample Data", "Reminder preview", "Saved (fixture)", "Notifications off", "Records at threshold"]

    /// One launch per fixture, preselected by launch argument, so no menu has
    /// to be driven at the largest text.
    private func run(_ arguments: [String], label: String) {
        for fixture in Self.fixtures {
            app = XCUIApplication()
            app.launchArguments = ["-AuroraDesignGallery", "-AuroraGalleryExperience", "cutoffScenario", "-AuroraGalleryCutoff", fixture] + arguments
            app.launch()
            XCTAssertTrue(app.navigationBars["Aurora Design Gallery"].waitForExistence(timeout: 15))
            let title = app.descendants(matching: .any)["assistant-card-cutoffScenario"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10), fixture)
            // Card start, then one screen further for the result and actions.
            for _ in 0..<12 where title.frame.minY > app.windows.firstMatch.frame.height * 0.3 { app.swipeUp() }
            capture("\(label) · \(fixture) · start")
            app.swipeUp()
            capture("\(label) · \(fixture) · result")
            app.terminate()
        }
    }

    func testCaptureDefaultText() { run([], label: "default") }

    func testCaptureLargestText() {
        run(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], label: "largest")
    }
}
