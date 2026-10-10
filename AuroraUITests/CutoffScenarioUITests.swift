import XCTest

/// Cutoff scenarios end to end. Every launch passes
/// `-AuroraUITestCutoffReminder`, so Save uses the injected outcome and never
/// reaches the notification center or asks for permission.
final class CutoffScenarioUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(reminder: String = "failed") {
        app = XCUIApplication()
        app.launchArguments = ["-AuroraUITestReset", "-AuroraUITestCutoffReminder", reminder]
        app.launch()
        tapWhenReady(app.buttons["onboarding-skip-story"], timeout: 15)
        tapWhenReady(app.buttons["setup-skip-all"])
        tapWhenReady(app.buttons["setup-finish"])
        XCTAssertTrue(app.textFields["assistant-composer"].waitForExistence(timeout: 10) || app.textViews["assistant-composer"].exists)
    }

    override func setUpWithError() throws { continueAfterFailure = false }

    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), element.debugDescription)
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: timeout), .completed)
        element.tap()
    }

    /// Scrolls the conversation until `element` can be tapped.
    private func reveal(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), element.debugDescription)
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, element.debugDescription)
    }

    /// The quick action sits past the first screen of the strip.
    private func openScenario() {
        let button = app.buttons["assistant-quick-Cutoff scenario"]
        let strip = app.scrollViews["assistant-quick-actions"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        for _ in 0..<6 where !(button.isHittable && button.frame.maxX < strip.frame.maxX - 8) {
            strip.swipeLeft()
        }
        button.tap()
        XCTAssertTrue(app.descendants(matching: .any)["assistant-card-cutoffScenario"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    private func type(_ text: String, into id: String) {
        let field = app.textFields[id]
        reveal(field)
        field.tap(); field.typeText(text)
        tapWhenReady(app.buttons["cutoff-keyboard-done"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }

    /// Adds a bedtime and moves its date to tomorrow with the native picker,
    /// keeping the current time of day: a time the test picks, never a proposal.
    private func bedtimeTomorrow() {
        reveal(app.buttons["cutoff-add-bedtime"])
        app.buttons["cutoff-add-bedtime"].tap()
        let picker = app.datePickers["cutoff-bedtime-date"]
        reveal(picker)
        picker.tap()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        if !Calendar.current.isDate(tomorrow, equalTo: .now, toGranularity: .month) {
            tapWhenReady(app.buttons["Next Month"])
        }
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US"); format.dateFormat = "MMMM d"
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", format.string(from: tomorrow))).firstMatch
        tapWhenReady(day)
        let dismiss = app.otherElements["PopoverDismissRegion"]
        if dismiss.waitForExistence(timeout: 2) { dismiss.tap() }
    }

    private func calculate() {
        let button = app.buttons["cutoff-calculate"]
        reveal(button)
        button.tap()
    }

    private func label(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testQuickActionOpensEmptyScenarioAndCalculateNeedsInputs() {
        launch()
        openScenario()
        let threshold = app.textFields["cutoff-threshold"]
        reveal(threshold)
        // No threshold, amount or bedtime is filled in for the person.
        XCTAssertTrue((threshold.value as? String ?? "").isEmpty || threshold.value as? String == "Enter mg")
        XCTAssertTrue(app.buttons["cutoff-add-bedtime"].exists)
        calculate()
        XCTAssertTrue(label(containing: "Needs inputs").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["cutoff-reminder-preview"].exists)
    }

    func testCalculateShowsResultAndFailedSaveHasNoReceipt() {
        launch(reminder: "failed")
        openScenario()
        bedtimeTomorrow()
        type("50", into: "cutoff-threshold")
        type("100", into: "cutoff-amount")
        calculate()
        XCTAssertTrue(label(containing: "Modeled caffeine at bedtime").waitForExistence(timeout: 5))
        XCTAssertTrue(label(containing: "Latest hypothetical time").exists)
        let preview = app.buttons["cutoff-reminder-preview"]
        reveal(preview); preview.tap()
        XCTAssertTrue(label(containing: "not a safety limit").waitForExistence(timeout: 5))
        let save = app.buttons["cutoff-reminder-save"]
        reveal(save); save.tap()
        XCTAssertTrue(app.staticTexts["assistant-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(label(containing: "couldn’t be scheduled").exists)
        XCTAssertTrue(label(containing: "Reminder not scheduled").exists)
        XCTAssertFalse(label(containing: "Scenario reminder scheduled").exists)
    }

    func testNotificationsOffExplainsHowToEnableWithoutAReceipt() {
        launch(reminder: "notAllowed")
        openScenario()
        bedtimeTomorrow()
        type("50", into: "cutoff-threshold")
        type("100", into: "cutoff-amount")
        calculate()
        let preview = app.buttons["cutoff-reminder-preview"]
        reveal(preview); preview.tap()
        let save = app.buttons["cutoff-reminder-save"]
        reveal(save); save.tap()
        XCTAssertTrue(label(containing: "allow Aurora in iOS Settings").waitForExistence(timeout: 5))
        XCTAssertFalse(label(containing: "Scenario reminder scheduled").exists)
    }

    func testExplicitSaveWithInjectedSuccessShowsOneReceipt() {
        launch(reminder: "scheduled")
        openScenario()
        bedtimeTomorrow()
        type("50", into: "cutoff-threshold")
        type("100", into: "cutoff-amount")
        calculate()
        let preview = app.buttons["cutoff-reminder-preview"]
        reveal(preview); preview.tap()
        let save = app.buttons["cutoff-reminder-save"]
        reveal(save); save.tap()
        XCTAssertTrue(label(containing: "Scenario reminder scheduled").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cutoff-reminder-save"].exists)
    }
}
