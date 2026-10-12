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

    private func choose(_ pickerID: String, _ option: String) {
        let picker = app.buttons[pickerID]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        for _ in 0..<8 where !picker.isHittable { app.swipeDown() }
        picker.tap()
        let item = app.buttons[option].firstMatch
        // At the largest text the menu scrolls; later options start off screen.
        _ = item.waitForExistence(timeout: 3)
        for _ in 0..<10 where !(item.exists && item.isHittable) { app.swipeUp() }
        XCTAssertTrue(item.waitForExistence(timeout: 5), option)
        item.tap()
    }

    private func run(_ arguments: [String], label: String) {
        app = XCUIApplication()
        app.launchArguments = ["-AuroraDesignGallery"] + arguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Aurora Design Gallery"].waitForExistence(timeout: 15))
        choose("gallery-experience", "cutoffScenario")
        for fixture in ["Empty inputs", "Time ahead", "Invalid inputs", "Sample Data", "Reminder preview", "Saved (fixture)", "Notifications off", "Records at threshold"] {
            choose("gallery-cutoff-variant", fixture)
            let title = app.descendants(matching: .any)["assistant-card-cutoffScenario"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10), fixture)
            // Card start, then one screen further for the result and actions.
            for _ in 0..<12 where title.frame.minY > app.windows.firstMatch.frame.height * 0.3 { app.swipeUp() }
            capture("\(label) · \(fixture) · start")
            app.swipeUp()
            capture("\(label) · \(fixture) · result")
            for _ in 0..<12 where !app.buttons["gallery-cutoff-variant"].isHittable { app.swipeDown() }
        }
    }

    func testCaptureDefaultText() { run([], label: "default") }

    func testCaptureLargestText() {
        run(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], label: "largest")
    }
}
