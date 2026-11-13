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
            // A fixed row of tiles, not a scroll view.
            let strip = app.descendants(matching: .any)["assistant-quick-actions"].firstMatch
            let window = app.windows.firstMatch
            let navigation = app.navigationBars.firstMatch
            let ceiling = navigation.exists ? navigation.frame.maxY + 8 : window.frame.minY + 8
            let floor = strip.exists ? strip.frame.minY - 8 : window.frame.maxY
            return element.isHittable && element.frame.minY > ceiling && element.frame.maxY < floor
        }
        // Drag toward the element: a drag that overshoots leaves it above
        // the bar, and dragging up again only moves it further away.
        let bar = app.navigationBars.firstMatch
        for _ in 0..<10 where !clear() {
            let window = app.windows.firstMatch
            let navigation = app.navigationBars.firstMatch
            let ceiling = navigation.exists ? navigation.frame.maxY + 8 : window.frame.minY + 8
            // A previous reveal can leave the next control above the viewport.
            // Always dragging up moves it farther away (CI #48: y = -80.3).
            let targetY: CGFloat = element.frame.minY <= ceiling ? 0.75 : 0.3
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).press(forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: targetY)))
        }
        XCTAssertTrue(clear(), element.debugDescription)
    }

    /// Not one of the four quick tiles, so it's asked for the way a person
    /// would: typed into the composer.
    /// `settle` is how long a send may take to clear the field before a
    /// retry is considered; 0 forces the retry path.
    private func openScenario(settle: TimeInterval = 2) {
        let input = app.textFields["assistant-composer"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("Cutoff scenario")
        // Sending clears the field, so a retry can never send twice.
        SendRetry.send(text: "Cutoff scenario", input: input, send: app.buttons["assistant-send"], settle: settle)
        XCTAssertTrue(app.descendants(matching: .any)["assistant-card-cutoffScenario"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), app.debugDescription)
    }

    private func type(_ text: String, into id: String) {
        let field = app.textFields[id]
        reveal(field)
        field.tap(); field.typeText(text)
        // iPhone shows the toolbar Done above the decimal pad; iPad's keyboard
        // has its own hide key and a return key instead.
        let done = app.buttons["cutoff-keyboard-done"]
        let hide = app.keyboards.buttons["Hide keyboard"]
        if done.waitForExistence(timeout: 2) && done.isHittable { done.tap() }
        else if hide.exists && hide.isHittable { hide.tap() }
        else { field.typeText("\n") }
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
        _ = dismiss.waitForExistence(timeout: 3)
        // Dismiss on the navigation bar's title, never at the region's own
        // hit point: on iPad that is (482, 688), inside cutoff-amount
        // (y 683.5-705.5), and iPadOS can hand the dismissing tap on to the
        // field (run 41988988325). Its decimal pad then opens in a popover
        // with its own PopoverDismissRegion, which this check would wait on
        // instead. The bar's center is the static "Aurora" title on iPad and
        // iPhone; its buttons sit at the edges.
        let bar = app.navigationBars.firstMatch
        let above = bar.exists ? bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            : app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04))
        above.tap()
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

    func testRequestOpensEmptyScenarioAndCalculateNeedsInputs() {
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

    /// A retry after the request already went out must not tap the disabled
    /// Send: that focuses the composer, and its keyboard hides the card's
    /// fields. `settle: 0` always reaches the retry; the old loop re-tapped.
    func testSendRetryLeavesTheKeyboardDown() {
        launch()
        openScenario(settle: 0)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(label(containing: "You: Cutoff scenario").exists)
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
