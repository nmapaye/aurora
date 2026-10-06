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
        XCTFail("No \(name) tab. Tree: \(tree())", file: file, line: line)
    }

    /// The element tree on one line, for failure messages: job logs aren't
    /// always reachable, but annotations are.
    private func tree() -> String {
        String(app.debugDescription
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " | ")
            .prefix(6000))
    }

    /// Fails with the element tree when `element` doesn't appear.
    @discardableResult
    private func expectToAppear(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 5,
                                file: StaticString = #filePath, line: UInt = #line) -> Bool {
        if element.waitForExistence(timeout: timeout) { return true }
        XCTFail("\(what) did not appear. Tree: \(tree())", file: file, line: line)
        return false
    }

    private func onScreen(_ title: String) -> XCUIElement {
        app.staticTexts["screen-title-\(title)"]
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
        let load = app.buttons["Load Sample Data"].firstMatch
        expectToAppear(load, "Load Sample Data on Summary")
        load.tap()
        expectToAppear(app.descendants(matching: .any)["summary-sample-status"], "the sample-data notice on Summary")
        tapTab("Log")
        expectToAppear(onScreen("Log"), "the Log screen")
        let sampleRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Sample Data, read-only'"))
            .firstMatch
        guard expectToAppear(sampleRow, "a read-only sample row on Log") else { return }
        sampleRow.tap()
        XCTAssertFalse(app.navigationBars["Edit Entry"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["dose-save"].exists, "Sample entries open no editor")
    }

    /// All ten steps in order, each on its own tab, with the tab bar locked
    /// throughout, then Finish unlocks it.
    func testWalkthroughRunsAllTenStepsAndFinishes() {
        finishManualSetup()
        let tabs = ["Summary", "Summary", "Summary", "Summary", "Sleep", "Sleep", "Log", "Log", "Insights", "Insights"]
        let next = app.buttons["walkthrough-next"]
        for (index, tab) in tabs.enumerated() {
            let step = index + 1
            expectToAppear(app.staticTexts["\(step) of 10"], "step \(step)'s progress")
            expectToAppear(onScreen(tab), "the \(tab) screen at step \(step)")
            if step == 7 {
                // A locked tap elsewhere leaves the walkthrough where it is.
                tapTab("Summary")
                expectToAppear(onScreen("Log"), "the Log screen after a locked tap")
                XCTAssertTrue(app.staticTexts["7 of 10"].exists)
            }
            XCTAssertEqual(next.label, step == 10 ? "Finish" : "Next")
            next.tap()
        }
        XCTAssertFalse(app.buttons["walkthrough-skip"].waitForExistence(timeout: 2), "The coach is gone after Finish")
        tapTab("Log")
        expectToAppear(onScreen("Log"), "the Log screen after the walkthrough")
    }

    /// The walkthrough resumes at the saved step after the app is relaunched.
    func testWalkthroughResumesAfterRelaunch() {
        finishManualSetup()
        let next = app.buttons["walkthrough-next"]
        for step in 1...5 {
            expectToAppear(app.staticTexts["\(step) of 10"], "step \(step)'s progress")
            next.tap()
        }
        expectToAppear(app.staticTexts["6 of 10"], "step 6 before relaunch")
        app.terminate()
        app.launchArguments = []
        app.launch()
        expectToAppear(app.staticTexts["6 of 10"], "step 6 after relaunch", timeout: 10)
        expectToAppear(onScreen("Sleep"), "the Sleep screen after relaunch")
    }
}
