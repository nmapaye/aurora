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
            // Card start, then the actual result. At the largest text one
            // swipe still showed the inputs, despite the attachment's name.
            for _ in 0..<12 where title.frame.minY > app.windows.firstMatch.frame.height * 0.3 { app.swipeUp() }
            capture("\(label) · \(fixture) · start")
            let destination = fixture == "Empty inputs"
                ? app.buttons["cutoff-calculate"]
                : app.staticTexts.matching(NSPredicate(format: "label == 'Result' OR label == 'RESULT'")).firstMatch
            XCTAssertTrue(destination.waitForExistence(timeout: 10), fixture)
            let window = app.windows.firstMatch
            for _ in 0..<40 where !destination.isHittable || destination.frame.minY > window.frame.height * 0.45 {
                // Short drags avoid flinging a large-type heading above the
                // viewport while trying to reveal it.
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(
                    forDuration: 0.05,
                    thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                    withVelocity: .slow, thenHoldForDuration: 0.05)
            }
            XCTAssertTrue(destination.isHittable, "\(fixture): expected the captured result/Calculate control on screen")
            XCTAssertGreaterThanOrEqual(destination.frame.minY, app.navigationBars.firstMatch.frame.maxY - 1)
            capture("\(label) · \(fixture) · \(fixture == "Empty inputs" ? "Calculate inputs" : "result heading")")
            app.terminate()
        }
    }

    func testCaptureDefaultText() { run([], label: "default") }

    func testCaptureLargestText() {
        run(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], label: "largest")
    }
}
