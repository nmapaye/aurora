import XCTest

/// End-to-end checks on a fresh install: setup, the walkthrough's tab lock,
/// Quick Add with Undo, and read-only Sample Data.
final class AuroraUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AuroraUITestReset"]
        app.launch()
    }

    private func finishManualSetup() {
        let next = app.buttons["onboarding-continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        app.buttons["source-manual"].tap()
        next.tap()
        next.tap()
    }

    func testWalkthroughLocksTabsUntilSkipped() {
        finishManualSetup()
        let skip = app.buttons["walkthrough-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        app.tabBars.buttons["Log"].tap()
        XCTAssertFalse(app.buttons["quick-add-drip"].waitForExistence(timeout: 1), "Tabs stay locked during the walkthrough")
        skip.tap()
        app.tabBars.buttons["Log"].tap()
        XCTAssertTrue(app.buttons["quick-add-drip"].waitForExistence(timeout: 5))
    }

    func testQuickAddThenUndo() {
        finishManualSetup()
        app.buttons["walkthrough-skip"].tap()
        app.tabBars.buttons["Log"].tap()
        app.buttons["quick-add-drip"].tap()
        let undo = app.buttons["quick-add-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        let loggedToday = app.descendants(matching: .any)["logged-today"]
        XCTAssertTrue(loggedToday.label.contains("95 mg"), loggedToday.label)
        undo.tap()
        XCTAssertTrue(loggedToday.label.contains("Nothing logged yet today."), loggedToday.label)
    }

    func testSampleEntriesAreReadOnly() {
        finishManualSetup()
        app.buttons["walkthrough-skip"].tap()
        app.buttons["Load Sample Data"].firstMatch.tap()
        app.tabBars.buttons["Log"].tap()
        let sampleRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Sample Data, read-only'"))
            .firstMatch
        XCTAssertTrue(sampleRow.waitForExistence(timeout: 5))
        sampleRow.tap()
        XCTAssertFalse(app.navigationBars["Edit Entry"].waitForExistence(timeout: 1))
    }
}
