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

    /// Taps a tab. The iPhone tab bar is not always reported as a tab bar,
    /// so a plain button with the tab's label is the fallback.
    private func tapTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let inBar = app.tabBars.buttons[name]
        if inBar.waitForExistence(timeout: 3) {
            inBar.tap()
            return
        }
        let plain = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
        if plain.waitForExistence(timeout: 2) {
            plain.tap()
            return
        }
        let tree = app.debugDescription
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " | ")
        XCTFail("No \(name) tab. Tree: \(tree.prefix(6000))", file: file, line: line)
    }

    func testWalkthroughLocksTabsUntilSkipped() {
        finishManualSetup()
        let skip = app.buttons["walkthrough-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        tapTab("Log")
        XCTAssertFalse(app.buttons["quick-add-drip"].waitForExistence(timeout: 1), "Tabs stay locked during the walkthrough")
        skip.tap()
        tapTab("Log")
        XCTAssertTrue(app.buttons["quick-add-drip"].waitForExistence(timeout: 5))
    }

    func testQuickAddThenUndo() {
        finishManualSetup()
        app.buttons["walkthrough-skip"].tap()
        tapTab("Log")
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
        tapTab("Log")
        let sampleRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Sample Data, read-only'"))
            .firstMatch
        XCTAssertTrue(sampleRow.waitForExistence(timeout: 5))
        sampleRow.tap()
        XCTAssertFalse(app.navigationBars["Edit Entry"].waitForExistence(timeout: 1))
    }
}
