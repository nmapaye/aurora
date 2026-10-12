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
        // The composer inset floats over the conversation's bottom edge, and
        // XCUITest still calls an element under it hittable. Keep scrolling
        // until the element sits fully above the quick actions and composer.
        func clear() -> Bool {
            let strip = app.scrollViews["assistant-quick-actions"]
            let floor = strip.exists ? strip.frame.minY - 8 : app.windows.firstMatch.frame.maxY
            return element.isHittable && element.frame.maxY < floor
        }
        for _ in 0..<10 where !clear() {
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).press(forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        }
        XCTAssertTrue(clear(), element.debugDescription)
    }

    /// The quick action sits past the first screen of the strip.
    private func openScenario() {
        let button = app.buttons["assistant-quick-Cutoff scenario"]
        let strip = app.scrollViews["assistant-quick-actions"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        // Same frame-based scroll as AuroraUITests.tapQuick: isHittable
        // can't be asked of an action scrolled out of the strip.
        for _ in 0..<6 {
            let frame = strip.frame
            let center = button.frame.midX
            if center > frame.minX + 12 && center < frame.maxX - 12 { break }
            let delta = min(0.65, max(-0.65, (center - frame.midX) / frame.width))
            let start = delta > 0 ? 0.85 : 0.15
            strip.coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.5)).press(forDuration: 0.1,
                thenDragTo: strip.coordinate(withNormalizedOffset: CGVector(dx: start - delta, dy: 0.5)))
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
        // The calendar popover covers the card until dismissed; its dismiss
        // region is a button or an other element depending on iOS.
        let dismiss = app.descendants(matching: .any)["PopoverDismissRegion"].firstMatch
        if dismiss.waitForExistence(timeout: 3) { dismiss.tap() }
        else { app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap() }
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 5), app.debugDescription)
    }

    /// Kept for review whether the test passes or not.
    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways
        add(shot)
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
        snapshot("after-save")
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
        snapshot("after-save")
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
        snapshot("after-save")
        XCTAssertTrue(label(containing: "Scenario reminder scheduled").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cutoff-reminder-save"].exists)
    }
}
