import XCTest

final class AuroraUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AuroraUITestReset"]
        app.launch()
    }
    /// Skips the story and the optional setup questions without requesting
    /// Health or calendar access, then finishes.
    private func finishSetup() {
        tapWhenReady(app.buttons["onboarding-skip-story"], timeout: 15)
        tapWhenReady(app.buttons["setup-skip-all"])
        tapWhenReady(app.buttons["setup-finish"])
        XCTAssertTrue(app.textFields["assistant-composer"].waitForExistence(timeout: 10) || app.textViews["assistant-composer"].exists)
    }
    /// Kept for visual review; not an assertion.
    private func attachScreenshot(_ name: String) {
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = name
        capture.lifetime = .keepAlways
        add(capture)
    }
    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: timeout), .completed)
        element.tap()
    }
    /// Taps a field and types once it really has keyboard focus. On a large
    /// iPad the keyboard appearing and the quick actions hiding move the
    /// layout under the tap, so a single tap can land beside the field.
    private func enter(_ text: String, into field: XCUIElement) {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        // A field just above the composer can sit partly under its bar, and a
        // tap there focuses the composer instead. Drag the conversation a
        // fixed distance until the field is clear of it.
        let composer = app.textFields["assistant-composer"]
        for _ in 0..<4 where composer.exists && field.frame.maxY > composer.frame.minY - 24 {
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(
                forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)),
                withVelocity: .slow, thenHoldForDuration: 0.05)
        }
        for _ in 0..<3 {
            field.tap()
            if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)], timeout: 2) == .completed { break }
        }
        field.typeText(text)
    }
    private func tapQuick(_ label: String) {
        let button = app.buttons["assistant-quick-" + label]
        // Only four quick actions remain; others are the same request typed.
        if !button.waitForExistence(timeout: 3) { request(label); return }
        let strip = app.scrollViews["assistant-quick-actions"]
        // The quick actions are a fixed row of tiles now; no scrolling needed.
        guard strip.exists else { button.tap(); return }
        for _ in 0..<5 {
            let frame = strip.frame
            let center = button.frame.midX
            if center > frame.minX + 12 && center < frame.maxX - 12 { break }
            let delta = min(0.65, max(-0.65, (center - frame.midX) / frame.width))
            let start = delta > 0 ? 0.85 : 0.15
            strip.coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.5)).press(forDuration: 0.1,
                thenDragTo: strip.coordinate(withNormalizedOffset: CGVector(dx: start - delta, dy: 0.5)))
        }
        button.tap()
    }
    /// A relaunch shows the welcome, which ends by itself after a few
    /// seconds. Wait it out rather than tapping it: on a slow runner it can
    /// end between being found and being tapped. Tap-to-skip has its own test.
    private func dismissWelcome() {
        let welcome = app.descendants(matching: .any)["welcome"]
        if welcome.waitForExistence(timeout: 5) {
            XCTAssertTrue(welcome.waitForNonExistence(timeout: 15))
        }
    }
    /// Apple Health lives in Aurora settings, not the quick actions.
    private func openAppleHealth() {
        tapWhenReady(app.buttons["assistant-settings"], timeout: 10)
        tapWhenReady(app.buttons["assistant-apple-health"])
    }
    func testAppleHealthConnectionIsReachableWithoutRequestingAccess() {
        finishSetup()
        openAppleHealth()
        XCTAssertTrue(app.staticTexts["assistant-health-disclosure"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assistant-health-connect"].exists)
        app.buttons["assistant-health-done"].tap()
        XCTAssertTrue(app.navigationBars["Aurora settings"].waitForExistence(timeout: 5))
    }

    func testHealthChoicesRemainReachableAtLargestTextWithoutRequestingAccess() {
        app.terminate()
        app.launchArguments = ["-AuroraUITestReset", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        finishSetup()
        openAppleHealth()
        XCTAssertTrue(app.staticTexts["assistant-health-disclosure"].waitForExistence(timeout: 5))
        let titles = ["readSleep": "Read sleep", "readCaffeine": "Read caffeine", "writeCaffeine": "Add my caffeine to Health", "backgroundUpdates": "Update in the background"]
        for choice in ["readSleep", "readCaffeine", "writeCaffeine", "backgroundUpdates"] {
            let control = app.switches["assistant-health-" + choice]
            XCTAssertTrue(control.exists)
            // The stacked layout hides the visual title; the switch still announces it.
            XCTAssertEqual(control.label, titles[choice])
            func reachable() -> Bool {
                if control.isEnabled { return control.isHittable }
                // The switch's label carries its description, so at the
                // largest text one row can be taller than the screen. A
                // disabled row counts once it shows below the bar.
                let shown = app.frame.insetBy(dx: 0, dy: 100)
                return control.frame.intersects(shown) && control.frame.minY < shown.maxY - 44
            }
            // Short drags toward the switch: on iPad the sheet is small at the
            // largest text, and a full swipe scrolled past it to the end.
            let window = app.windows.firstMatch
            for _ in 0..<24 where !reachable() {
                let up = control.frame.midY > window.frame.midY
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.6 : 0.4)).press(
                    forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.45 : 0.55)),
                    withVelocity: .slow, thenHoldForDuration: 0.05)
            }
            XCTAssertTrue(reachable(), choice + " must be reachable by scrolling")
            XCTAssertEqual(control.value as? String, "0", "Inspection must not enable Health access")
        }
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Health choices at largest text"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["assistant-health-done"].tap()
        XCTAssertTrue(app.buttons["assistant-send"].waitForExistence(timeout: 5))
    }

    func testFullEraseReturnsToSetupAcrossRelaunch() {
        finishSetup()
        tapQuick("Log caffeine")
        app.buttons["assistant-settings"].tap()
        XCTAssertTrue(app.navigationBars["Aurora settings"].waitForExistence(timeout: 5))
        let records = app.buttons["assistant-record-settings"]
        for _ in 0..<8 where !records.isHittable { app.swipeUp() }
        XCTAssertTrue(records.isHittable)
        records.tap()
        let erase = app.buttons["erase-all-local-data"]
        for _ in 0..<8 where !erase.isHittable { app.swipeUp() }
        XCTAssertTrue(erase.isHittable)
        erase.tap()
        XCTAssertTrue(app.alerts["Erase all local Aurora data?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Erase all local data"].tap()
        XCTAssertTrue(app.buttons["onboarding-skip-story"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["onboarding-skip-story"].waitForExistence(timeout: 10))
    }

    func testStoryLeadsIntoSetupThatSkipsEachStepAndResumesAfterRelaunch() {
        let next = app.buttons["story-continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        attachScreenshot("First story scene")
        next.tap(); next.tap()
        XCTAssertTrue(app.buttons["Begin setup"].waitForExistence(timeout: 5))
        next.tap()
        let field = app.textFields["setup-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Sam")
        tapWhenReady(app.buttons["setup-next"])
        XCTAssertTrue(app.staticTexts["setup-question-sleepTarget"].waitForExistence(timeout: 5))
        tapWhenReady(app.buttons["setup-next"])
        XCTAssertTrue(app.staticTexts["setup-question-health"].waitForExistence(timeout: 5))
        // Inspecting Health choices requests nothing.
        for choice in ["readSleep", "readCaffeine", "writeCaffeine"] where app.switches["setup-health-" + choice].exists {
            XCTAssertEqual(app.switches["setup-health-" + choice].value as? String, "0")
        }
        app.terminate(); app.launchArguments = []; app.launch()
        // Resumes at Health with the earlier answer kept; no story again.
        XCTAssertTrue(app.staticTexts["setup-question-health"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding-skip-story"].exists)
        XCTAssertTrue(app.staticTexts["You: Sam"].exists)
        // The target was confirmed with Continue, so it is shown as the person's answer.
        XCTAssertTrue(app.staticTexts["You: 8 hours"].exists)
        tapWhenReady(app.buttons["setup-skip"])
        XCTAssertTrue(app.staticTexts["setup-question-calendar"].waitForExistence(timeout: 5))
        tapWhenReady(app.buttons["setup-skip"])
        XCTAssertTrue(app.staticTexts["setup-question-wakeReminders"].waitForExistence(timeout: 5))
        tapWhenReady(app.buttons["setup-skip"])
        tapWhenReady(app.buttons["setup-finish"])
        XCTAssertTrue(app.buttons["assistant-send"].waitForExistence(timeout: 10))
    }

    func testWakeRemindersChosenInSetupShowInTranscriptAndSettings() {
        tapWhenReady(app.buttons["onboarding-skip-story"], timeout: 15)
        for step in ["sleepTarget", "health", "calendar", "wakeReminders"] {
            tapWhenReady(app.buttons["setup-skip"])
            XCTAssertTrue(app.staticTexts["setup-question-" + step].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.staticTexts["wake-preview"].exists)
        // Nothing is chosen for the person: no time is selected and the
        // primary action waits for a pick.
        XCTAssertFalse(app.buttons["wake-offset-60"].isSelected)
        XCTAssertFalse(app.buttons["setup-next"].isEnabled)
        tapWhenReady(app.buttons["wake-offset-60"])
        tapWhenReady(app.buttons["wake-offset-120"])
        tapWhenReady(app.buttons["setup-next"])
        // Notification permission is asked only now, after the explicit choice.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(app.staticTexts["You: 1h and 2h after waking"].waitForExistence(timeout: 5))
        tapWhenReady(app.buttons["setup-finish"])
        tapWhenReady(app.buttons["assistant-settings"], timeout: 10)
        let entry = app.buttons["assistant-wake-reminders"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.label.contains("+1h, +2h"))
    }

    func testSkipToEndShowsNoAnswersForQuestionsNotAsked() {
        tapWhenReady(app.buttons["onboarding-skip-story"], timeout: 15)
        tapWhenReady(app.buttons["setup-skip-all"])
        XCTAssertTrue(app.buttons["setup-finish"].waitForExistence(timeout: 5))
        for step in ["name", "sleepTarget", "health", "calendar", "wakeReminders"] {
            XCTAssertFalse(app.staticTexts["setup-question-" + step].exists, step + " was never asked")
        }
        XCTAssertFalse(app.staticTexts["You: 8 hours"].exists)
        XCTAssertFalse(app.staticTexts["You: Not now"].exists)
    }

    func testSleepTargetNotNowKeepsTheSettingAsAuroraNote() {
        tapWhenReady(app.buttons["onboarding-skip-story"], timeout: 15)
        tapWhenReady(app.buttons["setup-skip"])
        XCTAssertTrue(app.staticTexts["setup-question-sleepTarget"].waitForExistence(timeout: 5))
        // Change the shown value, then decline: the stored target stays.
        app.steppers["setup-sleep-target"].buttons.element(boundBy: 1).tap()
        tapWhenReady(app.buttons["setup-skip"])
        XCTAssertTrue(app.staticTexts["setup-question-health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You: Not now"].exists)
        XCTAssertTrue(app.staticTexts["setup-retained-sleepTarget"].exists)
        XCTAssertTrue(app.staticTexts["setup-retained-sleepTarget"].label.contains("8 hours"))
        XCTAssertFalse(app.staticTexts["You: 8 hours"].exists)
        XCTAssertFalse(app.staticTexts["You: 8.5 hours"].exists)
    }

    func testHealthSetupAtLargestTextRequestsNothing() {
        app.terminate()
        app.launchArguments = ["-AuroraUITestReset", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tapWhenReady(app.buttons["onboarding-skip-story"], timeout: 15)
        tapWhenReady(app.buttons["setup-skip"])
        XCTAssertTrue(app.staticTexts["setup-question-sleepTarget"].waitForExistence(timeout: 5))
        tapWhenReady(app.buttons["setup-skip"])
        XCTAssertTrue(app.staticTexts["setup-question-health"].waitForExistence(timeout: 5))
        for choice in ["readSleep", "readCaffeine", "writeCaffeine"] {
            let control = app.switches["setup-health-" + choice]
            XCTAssertTrue(control.exists)
            XCTAssertEqual(control.value as? String, "0", "Inspection must not enable Health access")
        }
        XCTAssertTrue(app.buttons["setup-skip"].exists)
        attachScreenshot("Health setup at largest text")
    }

    func testWelcomeGreetsByNameAndATapSkipsAtOnce() {
        tapWhenReady(app.buttons["onboarding-skip-story"], timeout: 15)
        let field = app.textFields["setup-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Sam")
        tapWhenReady(app.buttons["setup-next"])
        tapWhenReady(app.buttons["setup-skip-all"])
        tapWhenReady(app.buttons["setup-finish"])
        app.terminate(); app.launchArguments = ["-AuroraWelcomeHold"]; app.launch()
        let welcome = app.descendants(matching: .any)["welcome"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 10))
        XCTAssertTrue(welcome.label.contains("Sam"))
        XCTAssertTrue(welcome.label.contains("Ready when you are."))
        attachScreenshot("Held welcome")
        welcome.tap()
        // No dissolve to wait out: the conversation takes touches right away.
        let send = app.buttons["assistant-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["assistant-quick-Log caffeine"].isHittable)
    }

    func testDebugDesignGalleryUsesNativeSyntheticFixtures() {
        app.terminate(); app.launchArguments = ["-AuroraDesignGallery"]; app.launch()
        XCTAssertTrue(app.navigationBars["Aurora Design Gallery"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["assistant-dose-amount"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["Populate sample records"].exists)
        let health = app.buttons["gallery-health-choices"]
        for _ in 0..<12 where !health.isHittable { app.swipeUp() }
        health.tap()
        XCTAssertTrue(app.switches["assistant-health-backgroundUpdates"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["assistant-health-backgroundUpdates"].label, "Update in the background")
        app.buttons["assistant-health-done"].tap()
    }

    func testConversationHomeReplacesTabs() {
        finishSetup()
        XCTAssertTrue(app.buttons["assistant-history"].exists)
        XCTAssertTrue(app.buttons["assistant-settings"].exists)
        XCTAssertEqual(app.tabBars.count, 0)
        tapQuick("How is my energy?")
        XCTAssertTrue(app.otherElements["assistant-card-energy"].waitForExistence(timeout: 5) || app.staticTexts["Your energy signals"].waitForExistence(timeout: 5))
        // No score: the card leads with the missing record, not "Unavailable".
        let missing = app.descendants(matching: .any)["assistant-energy-missing"].firstMatch
        XCTAssertTrue(missing.waitForExistence(timeout: 5))
        XCTAssertTrue(missing.label.contains("No sleep recorded in the last 24 hours."), missing.label)
        XCTAssertFalse(app.staticTexts["Unavailable"].exists)
        XCTAssertTrue(app.buttons["Record sleep"].exists)
    }
    func testEnergyCurveShowsModeledLabelsWithoutRecords() {
        finishSetup()
        tapQuick("Show my energy curve")
        XCTAssertTrue(app.staticTexts["Modeled alertness · 24 hours"].waitForExistence(timeout: 5))
        let curve = app.otherElements["assistant-energy-curve"]
        XCTAssertTrue(curve.waitForExistence(timeout: 5))
        XCTAssertTrue(curve.label.contains("Modeled."))
        // Recorded inputs are shown only when asked for.
        XCTAssertFalse(app.staticTexts["No sleep or caffeine recorded in this window."].exists)
        // The typed request leaves the keyboard up, and the row can sit
        // behind it while still reporting hittable; reach it above both.
        let recorded = app.buttons["What’s recorded in this window"]
        let composer = app.textFields["assistant-composer"]
        let keyboard = app.keyboards.firstMatch
        func reachable() -> Bool {
            recorded.isHittable && recorded.frame.maxY <= composer.frame.minY
                && (!keyboard.exists || recorded.frame.maxY <= keyboard.frame.minY)
        }
        for _ in 0..<6 where !reachable() { app.swipeUp() }
        XCTAssertTrue(reachable(), "Row \(recorded.frame)")
        recorded.tap()
        XCTAssertTrue(app.staticTexts["No sleep or caffeine recorded in this window."].waitForExistence(timeout: 3))
    }

    func testCheckInNeedsARatingSaveAndUndo() {
        finishSetup()
        tapQuick("Check in my energy")
        let save = app.buttons["assistant-checkin-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["assistant-error"].waitForExistence(timeout: 3))
        let rating = app.segmentedControls["assistant-checkin-rating"]
        for _ in 0..<6 where !rating.isHittable { app.swipeDown() }
        rating.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(app.staticTexts["4 · High"].waitForExistence(timeout: 3))
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        save.tap()
        let undo = app.buttons["assistant-checkin-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        for _ in 0..<6 where !undo.isHittable { app.swipeUp() }
        undo.tap()
        XCTAssertTrue(app.staticTexts["Check-in removed"].waitForExistence(timeout: 5))
    }

    func testEnergyGalleryOffersSyntheticVariants() {
        app.terminate(); app.launchArguments = ["-AuroraDesignGallery"]; app.launch()
        XCTAssertTrue(app.navigationBars["Aurora Design Gallery"].waitForExistence(timeout: 10))
        // The menu picker's label includes its value ("Experience, caffeineDraft"),
        // so select it by identifier.
        let experience = app.buttons["gallery-experience"]
        XCTAssertTrue(experience.waitForExistence(timeout: 10))
        for _ in 0..<6 where !experience.isHittable { app.swipeDown() }
        XCTAssertTrue(experience.isHittable)
        experience.tap()
        let option = app.buttons["energyProjection"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        XCTAssertTrue(app.otherElements["assistant-energy-curve"].waitForExistence(timeout: 10))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Energy curve gallery fixture"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testCaffeineNeedsReviewAndUndoRemovesOnlySavedEntry() {
        finishSetup()
        app.buttons["assistant-quick-Log caffeine"].tap()
        let amount = app.textFields["assistant-dose-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        let save = app.buttons["assistant-dose-save"]
        tapWhenReady(save)
        XCTAssertTrue(app.staticTexts["assistant-error"].waitForExistence(timeout: 5))
        enter("120", into: amount)
        let source = app.textFields["assistant-dose-source"]
        enter("Tea", into: source)
        // The whole-app swipe can hit the fixed quick-action strip while the
        // keyboard is open. Finish editing before tapping the reviewed draft.
        // A simulator with a connected hardware keyboard can expose an
        // offscreen keyboard preview. Send Return to the focused field
        // instead of tapping that preview's inaccessible button.
        source.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(save.isHittable)
        save.tap()
        let undo = app.buttons["assistant-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), app.debugDescription)
        undo.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Removed that caffeine entry'")).firstMatch.waitForExistence(timeout: 5))
    }
    func testDraftFieldKeepsSaveAboveCollapsedComposer() {
        finishSetup()
        let quick = app.buttons["assistant-quick-Log caffeine"]
        app.buttons["assistant-quick-Log caffeine"].tap()
        let amount = app.textFields["assistant-dose-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        let source = app.textFields["assistant-dose-source"]
        enter("Tea", into: source)
        // End on the numeric pad, which has no Return key to dismiss it.
        enter("80", into: amount)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(keyboard.keys["8"].exists || keyboard.buttons["8"].exists, "Expected the numeric pad")
        // While a card field is edited the composer keeps only its own field.
        XCTAssertTrue(quick.waitForNonExistence(timeout: 5))
        let composer = app.textFields["assistant-composer"]
        XCTAssertTrue(composer.exists)

        // Scroll the conversation itself until Save sits fully between the
        // screen top and the composer above the keyboard. Each drag starts
        // in the conversation, well above the composer and keyboard, and
        // holds at its end so it moves a fixed distance without a fling.
        let save = app.buttons["assistant-dose-save"]
        let window = app.windows.firstMatch
        func saveReachable() -> Bool {
            let frame = save.frame
            return save.isHittable && frame.height >= 44 && frame.minY >= window.frame.minY
                && frame.maxY <= composer.frame.minY && frame.maxY <= keyboard.frame.minY
        }
        for _ in 0..<6 where !saveReachable() {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(
                forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                withVelocity: .slow, thenHoldForDuration: 0.05
            )
        }
        // Kept for visual diagnosis whether or not the geometry passes.
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Draft Save with numeric keyboard"
        capture.lifetime = .keepAlways
        add(capture)
        XCTAssertTrue(keyboard.exists, "Save must be reachable while the numeric pad is up")
        XCTAssertTrue(saveReachable(), "Save \(save.frame) composer \(composer.frame) keyboard \(keyboard.frame)")
        XCTAssertTrue(quick.waitForNonExistence(timeout: 1))

        // Editing saved nothing; Save is the explicit step and works from here.
        XCTAssertFalse(app.buttons["assistant-undo"].exists)
        save.tap()
        XCTAssertTrue(app.buttons["assistant-undo"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Caffeine saved"].exists)
        XCTAssertFalse(save.exists)
        // The saved draft no longer has a field, so the keyboard leaves and
        // the quick actions return.
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        XCTAssertTrue(quick.isHittable)
    }
    func testOfflineChartAndNativeToolsAreReachable() {
        finishSetup()
        tapQuick("Show this week")
        XCTAssertTrue(app.staticTexts["Recorded caffeine · this week"].waitForExistence(timeout: 5))
        app.buttons["assistant-history"].tap()
        XCTAssertTrue(app.buttons["records-caffeine"].waitForExistence(timeout: 5))
        app.buttons["records-caffeine"].tap()
        XCTAssertTrue(app.navigationBars["Caffeine History"].waitForExistence(timeout: 5))
    }
    /// Screens pushed in Your records keep the system bar: sleep history
    /// opens in the same sheet, Back returns, and Done closes the sheet.
    func testRecordsScreensKeepBackAndDone() {
        finishSetup()
        app.buttons["assistant-history"].tap()
        XCTAssertTrue(app.buttons["records-sleep"].waitForExistence(timeout: 5))
        app.buttons["records-sleep"].tap()
        XCTAssertTrue(app.navigationBars["Sleep"].waitForExistence(timeout: 5))
        let data = app.buttons["sleep-data"]
        for _ in 0..<6 where !data.isHittable { app.swipeUp() }
        data.tap()
        let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'All sleep entries'")).firstMatch
        for _ in 0..<6 where !all.isHittable { app.swipeUp() }
        all.tap()
        XCTAssertTrue(app.navigationBars["Sleep History"].waitForExistence(timeout: 5))
        app.navigationBars["Sleep History"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Sleep"].waitForExistence(timeout: 5))
        app.navigationBars["Sleep"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Your records"].waitForExistence(timeout: 5))
        app.navigationBars["Your records"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["assistant-send"].waitForExistence(timeout: 5))
    }
    func testCalendarNeverWritesWithoutPreviewApproval() {
        finishSetup()
        tapQuick("Review calendar")
        XCTAssertTrue(app.buttons["Calendar connections"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["calendar-approve"].exists)
    }
    func testNoAPIKeyEntryInSettings() {
        finishSetup()
        app.buttons["assistant-settings"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'No cloud model'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields.containing(NSPredicate(format: "label CONTAINS[c] 'API key'")).firstMatch.exists)
    }
    func testInlineSleepSaveCreatesReceipt() {
        finishSetup()
        request("Log sleep")
        let save = app.buttons["assistant-sleep-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        // Both times start empty, so Save waits for the person's own.
        XCTAssertFalse(save.isEnabled)
        // End, then start, at the current minute; moving the start back a
        // day makes a night of just under (or exactly) 24 hours.
        tapWhenReady(app.buttons["assistant-sleep-add-end"])
        tapWhenReady(app.buttons["assistant-sleep-add-start"])
        let startDate = app.datePickers["assistant-sleep-start-date"]
        XCTAssertTrue(startDate.waitForExistence(timeout: 5))
        for _ in 0..<4 where !startDate.isHittable { app.swipeUp() }
        startDate.tap()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        if !Calendar.current.isDate(yesterday, equalTo: .now, toGranularity: .month) {
            tapWhenReady(app.buttons["Previous Month"])
        }
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US"); format.dateFormat = "MMMM d"
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", format.string(from: yesterday))).firstMatch)
        // The calendar popover covers the card until dismissed.
        let dismiss = app.descendants(matching: .any)["PopoverDismissRegion"].firstMatch
        if dismiss.waitForExistence(timeout: 3) { dismiss.tap() }
        else { app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap() }
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 5))
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["Sleep saved"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assistant-undo"].exists)
    }
    func testTrendsSwitchSignalsAndRange() {
        finishSetup()
        tapQuick("Show this week")
        let signals = app.segmentedControls["assistant-trend-metric"]
        XCTAssertTrue(signals.waitForExistence(timeout: 5))
        signals.buttons["Sleep"].tap()
        XCTAssertTrue(app.staticTexts["Recorded sleep · 7 days"].waitForExistence(timeout: 5))
        app.segmentedControls["assistant-trend-range"].buttons["Month"].tap()
        XCTAssertTrue(app.staticTexts["Recorded sleep · 30 days"].waitForExistence(timeout: 5))
        signals.buttons["Reaction"].tap()
        XCTAssertTrue(app.staticTexts["Recorded reaction · 30 days"].waitForExistence(timeout: 5))
    }
    func testExpiredDraftRequiresNewReviewAfterRelaunch() {
        finishSetup()
        app.buttons["assistant-quick-Log caffeine"].tap()
        XCTAssertTrue(app.textFields["assistant-dose-amount"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = []; app.launch()
        dismissWelcome()
        XCTAssertTrue(app.buttons["assistant-refresh-caffeineDraft"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["assistant-dose-save"].exists)
        app.buttons["assistant-refresh-caffeineDraft"].tap()
        XCTAssertTrue(app.buttons["assistant-dose-save"].waitForExistence(timeout: 5))
    }

    private func request(_ text: String) {
        let input = app.textFields["assistant-composer"]
        input.tap(); input.typeText(text)
        // The keyboard can still be moving the composer when the tap lands.
        // Sending clears the field, so a retry can never send twice.
        let cleared = NSPredicate(format: "value != %@", text)
        for _ in 0..<3 {
            app.buttons["assistant-send"].tap()
            if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: cleared, object: input)], timeout: 2) == .completed { break }
        }
    }
    func testExportCardOffersNativeCSVSharing() {
        finishSetup(); request("Export records")
        XCTAssertTrue(app.buttons["Sleep records CSV"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Caffeine entries CSV"].exists)
        XCTAssertTrue(app.buttons["Reaction tests CSV"].exists)
    }
    func testHistoryCardProvidesSearchAndSourceFilters() {
        finishSetup(); request("History")
        XCTAssertTrue(app.textFields["assistant-history-search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No matching records in this snapshot."].waitForExistence(timeout: 5))
    }
    func testBriefingAndReminderCards() {
        finishSetup(); request("Morning briefing")
        XCTAssertTrue(app.staticTexts["Your recorded day"].waitForExistence(timeout: 5))
        request("Reminders")
        XCTAssertTrue(app.switches["Offer useful updates"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["Cutoff reminder"].exists)
    }
    func testReactionCardOpensTheExistingTest() {
        finishSetup(); request("Reaction test")
        let start = app.buttons["assistant-reaction-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
        XCTAssertTrue(app.buttons["reaction-start"].waitForExistence(timeout: 5))
    }
    func testLargestAccessibilityTextKeepsCardsAndComposerReachable() {
        app.terminate()
        app.launchArguments = ["-AuroraUITestReset", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        finishSetup()
        // Tiles go icon-only rather than clip, keep their names, and stay
        // inside one row above the composer.
        let row = app.descendants(matching: .any)["assistant-quick-actions"].firstMatch
        let caffeine = app.buttons["assistant-quick-Log caffeine"]
        XCTAssertTrue(caffeine.waitForExistence(timeout: 5) && caffeine.isHittable)
        XCTAssertEqual(caffeine.label, "Log caffeine")
        XCTAssertTrue(row.frame.insetBy(dx: -1, dy: -1).contains(caffeine.frame), "tile \(caffeine.frame) row \(row.frame)")
        XCTAssertLessThanOrEqual(row.frame.maxY, app.textFields["assistant-composer"].frame.minY)
        request("Morning briefing")
        XCTAssertTrue(app.staticTexts["Your recorded day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["assistant-composer"].isHittable)
        XCTAssertTrue(app.buttons["assistant-send"].exists)
        request("Reminders")
        let reminder = app.switches["Cutoff reminder"]
        for _ in 0..<6 where !reminder.waitForExistence(timeout: 1) { app.swipeUp() }
        XCTAssertTrue(reminder.exists)
        for _ in 0..<4 where !reminder.isHittable { app.swipeUp() }
        XCTAssertTrue(reminder.isHittable)
    }

    // MARK: Polish regressions

    private func cardTitle(_ kind: String) -> XCUIElement {
        app.descendants(matching: .any)["assistant-card-\(kind)"].firstMatch
    }

    /// The composer sits in the cards' column: its field starts where card
    /// content starts (both 16 pt inside the column) and the column is centered,
    /// on iPhone and on iPad, whose cards are capped at 600 pt.
    func testComposerSharesTheCardColumn() {
        finishSetup()
        tapQuick("How is my energy?")
        let title = cardTitle("energy")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let composer = app.textFields["assistant-composer"]
        let send = app.buttons["assistant-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        attachScreenshot("Composer in the card column")
        XCTAssertEqual(composer.frame.minX, title.frame.minX, accuracy: 2, "composer \(composer.frame) title \(title.frame)")
        let leading = composer.frame.minX - window.minX
        let trailing = window.maxX - send.frame.maxX
        XCTAssertEqual(leading, trailing, accuracy: 2, "Column should be centered")
        // Field to Send spans the column less the composer's own 16 pt sides.
        XCTAssertLessThanOrEqual(send.frame.maxX - composer.frame.minX, 600 - 32 + 1)
        XCTAssertGreaterThanOrEqual(send.frame.width, 44)
    }

    /// A long card shows its title, not its last control, right after it arrives.
    func testLongCardArrivesShowingItsStart() {
        finishSetup()
        tapQuick("Show this week")
        XCTAssertTrue(cardTitle("trends").waitForExistence(timeout: 5))
        tapQuick("Show my energy curve")
        let title = cardTitle("energyProjection")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 3), .completed)
        let bar = app.navigationBars.firstMatch.frame
        XCTAssertGreaterThanOrEqual(title.frame.minY, bar.maxY - 1, "Title \(title.frame) under the bar \(bar)")
        XCTAssertLessThanOrEqual(title.frame.maxY, app.textFields["assistant-composer"].frame.minY)
        attachScreenshot("Long card start after insertion")
    }

    /// A draft asked for while typing takes the letter keyboard down and
    /// shows from its title, with no "New message below" over it.
    func testDraftFromATileWhileTypingDropsTheKeyboardAndShowsItsTitle() {
        finishSetup()
        let composer = app.textFields["assistant-composer"]
        composer.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        tapWhenReady(app.buttons["assistant-quick-Log caffeine"])
        let title = cardTitle("caffeineDraft")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 3), .completed)
        XCTAssertGreaterThanOrEqual(title.frame.minY, app.navigationBars.firstMatch.frame.maxY - 1, "Title \(title.frame)")
        XCTAssertLessThanOrEqual(title.frame.maxY, composer.frame.minY)
        XCTAssertFalse(app.buttons["assistant-new-below"].waitForExistence(timeout: 2))
        attachScreenshot("Draft from a tile while typing")
    }

    /// Saving an earlier draft while reading it adds a receipt at the end
    /// without moving the page; "New message below" then shows the receipt.
    func testReplyWhileReadingEarlierMessagesKeepsThePlace() {
        finishSetup()
        app.buttons["assistant-quick-Log caffeine"].tap()
        let amount = app.textFields["assistant-dose-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        // Longer cards after the draft, which stays open.
        tapQuick("Show my energy curve")
        XCTAssertTrue(cardTitle("energyProjection").waitForExistence(timeout: 5))
        tapQuick("Show this week")
        XCTAssertTrue(cardTitle("trends").waitForExistence(timeout: 5))
        tapQuick("How is my energy?")
        XCTAssertTrue(cardTitle("energy").waitForExistence(timeout: 5))

        let save = app.buttons["assistant-dose-save"]
        for _ in 0..<16 where !amount.isHittable { app.swipeDown() }
        XCTAssertTrue(amount.isHittable)
        enter("80", into: amount)
        // Same fixed-distance drags as the keyboard test, until Save is clear
        // of the composer and the number pad.
        let keyboard = app.keyboards.firstMatch
        let composer = app.textFields["assistant-composer"]
        func saveReachable() -> Bool {
            save.isHittable && save.frame.maxY <= composer.frame.minY
                && (!keyboard.exists || save.frame.maxY <= keyboard.frame.minY)
        }
        for _ in 0..<6 where !saveReachable() {
            window().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(
                forDuration: 0.05, thenDragTo: window().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                withVelocity: .slow, thenHoldForDuration: 0.05)
        }
        XCTAssertTrue(saveReachable(), "Save \(save.frame)")
        let before = save.frame
        save.tap()
        let below = app.buttons["assistant-new-below"]
        XCTAssertTrue(below.waitForExistence(timeout: 5), app.debugDescription)
        attachScreenshot("Reply held while reading earlier messages")
        // The saved draft stays where it was: its summary replaced Save in place.
        let savedNote = app.staticTexts["Saved. See the receipt below."]
        XCTAssertTrue(savedNote.waitForExistence(timeout: 5))
        XCTAssertEqual(savedNote.frame.minY, before.minY, accuracy: 200, "The page moved")
        XCTAssertTrue(savedNote.isHittable)
        below.tap()
        XCTAssertTrue(below.waitForNonExistence(timeout: 5))
        let undo = app.buttons["assistant-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        let receipt = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: undo)
        XCTAssertEqual(XCTWaiter.wait(for: [receipt], timeout: 3), .completed)
    }

    /// A long conversation renders its latest messages; earlier ones come a
    /// batch at a time, and the message that was first stays at the top.
    func testShowEarlierMessagesRevealsABatchAndKeepsThePlace() {
        app.terminate()
        app.launchArguments = ["-AuroraUITestReset", "-AuroraUITestLongConversation"]
        app.launch()
        finishSetup()
        func message(_ number: Int) -> XCUIElement {
            app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", ": Earlier message \(number)")).firstMatch
        }
        // 70 messages: the latest 40 (31 to 70) are shown.
        XCTAssertTrue(message(70).waitForExistence(timeout: 10))
        XCTAssertFalse(message(30).exists)
        let earlier = app.buttons["assistant-show-earlier"]
        for _ in 0..<20 where !earlier.isHittable { app.swipeDown() }
        XCTAssertTrue(earlier.isHittable)
        earlier.tap()
        XCTAssertTrue(message(11).waitForExistence(timeout: 5))
        XCTAssertFalse(message(10).exists)
        // The message that was first is at the top, with the batch above it.
        let top = message(31)
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: top)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 3), .completed)
        let bar = app.navigationBars.firstMatch.frame
        XCTAssertGreaterThanOrEqual(top.frame.minY, bar.maxY - 1, "Message \(top.frame) under the bar \(bar)")
        XCTAssertLessThanOrEqual(top.frame.minY, bar.maxY + 120, "The page jumped: \(top.frame)")
        XCTAssertLessThan(message(30).frame.maxY, top.frame.minY)
        attachScreenshot("Earlier messages shown above the place")
        // The last batch reaches the first message and the control goes.
        for _ in 0..<20 where !earlier.isHittable { app.swipeDown() }
        earlier.tap()
        XCTAssertTrue(message(1).waitForExistence(timeout: 5))
        XCTAssertTrue(earlier.waitForNonExistence(timeout: 5))
    }

    // MARK: Discovery

    /// A new conversation opens on the short welcome, read from its top;
    /// the full list of capabilities is one chip away, not the first card.
    func testNewConversationOpensOnTheWelcomeFromItsTop() {
        finishSetup()
        let welcome = cardTitle("welcome")
        XCTAssertTrue(welcome.waitForExistence(timeout: 5))
        XCTAssertEqual(welcome.label, "Ready when you are.")
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: welcome)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 3), .completed)
        XCTAssertGreaterThanOrEqual(welcome.frame.minY, app.navigationBars.firstMatch.frame.maxY - 1)
        XCTAssertFalse(cardTitle("capabilities").exists)
        for chip in ["logCaffeine", "logSleep", "help"] {
            XCTAssertTrue(app.buttons["welcome-" + chip].exists, chip)
        }
        let hint = app.staticTexts["Start with a quick action, or ask in your own words."]
        XCTAssertTrue(hint.exists)
        attachScreenshot("New conversation welcome")
        tapWhenReady(app.buttons["welcome-help"])
        XCTAssertTrue(cardTitle("capabilities").waitForExistence(timeout: 5))
        // The hint is for an empty conversation only.
        XCTAssertTrue(hint.waitForNonExistence(timeout: 3))
    }

    /// Clearing erases the conversation and opens it again on the welcome.
    func testClearConversationReturnsToTheWelcome() {
        finishSetup()
        XCTAssertTrue(cardTitle("welcome").waitForExistence(timeout: 5))
        request("help")
        XCTAssertTrue(cardTitle("capabilities").waitForExistence(timeout: 5))
        tapWhenReady(app.buttons["assistant-settings"])
        let clear = app.buttons["Clear conversation"].firstMatch
        for _ in 0..<8 where !clear.isHittable { app.swipeUp() }
        let row = clear.frame
        clear.tap()
        // On iOS 26 the dialog is a menu from the row; its button is the
        // other "Clear conversation".
        let matches = app.buttons.matching(identifier: "Clear conversation")
        let two = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: matches)
        XCTAssertEqual(XCTWaiter.wait(for: [two], timeout: 3), .completed)
        let confirm = matches.allElementsBoundByIndex.first { $0.frame != row }
        XCTAssertNotNil(confirm)
        confirm?.tap()
        XCTAssertTrue(cardTitle("capabilities").waitForNonExistence(timeout: 5))
        XCTAssertTrue(cardTitle("welcome").waitForExistence(timeout: 5))
        let back = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: app.buttons["welcome-help"])
        XCTAssertEqual(XCTWaiter.wait(for: [back], timeout: 5), .completed)
    }

    /// "help" answers with everything Aurora can do, not a clarification,
    /// and each row sends its own request. The welcome came first.
    func testHelpShowsCapabilitiesAndARowSendsItsRequest() {
        finishSetup()
        XCTAssertTrue(cardTitle("welcome").waitForExistence(timeout: 5))
        request("help")
        XCTAssertTrue(cardTitle("capabilities").waitForExistence(timeout: 5))
        XCTAssertFalse(cardTitle("clarification").exists)
        let cutoff = app.buttons["capability-cutoffScenario"].firstMatch
        for _ in 0..<6 where !cutoff.isHittable { app.swipeUp() }
        cutoff.tap()
        XCTAssertTrue(cardTitle("cutoffScenario").waitForExistence(timeout: 5))
    }

    /// While typing, the quick tiles become what matches the words so far.
    func testTypingOffersMatchingActionsInPlaceOfTiles() {
        finishSetup()
        XCTAssertTrue(app.buttons["assistant-quick-Morning briefing"].exists)
        let input = app.textFields["assistant-composer"]
        input.tap(); input.typeText("cut")
        let suggestion = app.buttons["assistant-suggest-cutoffScenario"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["assistant-quick-Morning briefing"].exists)
        // A suggestion covers a tile exactly; nothing spills onto the composer.
        let row = app.descendants(matching: .any)["assistant-quick-actions"].firstMatch
        XCTAssertTrue(row.frame.insetBy(dx: -1, dy: -1).contains(suggestion.frame), "suggestion \(suggestion.frame) row \(row.frame)")
        attachScreenshot("Composer suggestions")
        suggestion.tap()
        XCTAssertTrue(cardTitle("cutoffScenario").waitForExistence(timeout: 5))
        XCTAssertNotEqual(input.value as? String, "cut")
    }

    /// The newest answer's next steps lead the fixed row above the composer
    /// and send their request; the everyday tiles fill the rest.
    func testNextStepsLeadTheBottomRowAfterAnEnergyAnswer() {
        finishSetup()
        let row = app.descendants(matching: .any)["assistant-quick-actions"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let height = row.frame.height
        tapQuick("How is my energy?")
        XCTAssertTrue(cardTitle("energy").waitForExistence(timeout: 5))
        let curve = row.buttons["assistant-follow-up-energyProjection"]
        XCTAssertTrue(curve.waitForExistence(timeout: 5))
        // Next steps replace tiles without changing the row's height.
        XCTAssertEqual(row.frame.height, height, accuracy: 1)
        XCTAssertTrue(row.buttons["assistant-follow-up-energyCheckIn"].exists)
        XCTAssertTrue(row.buttons["assistant-quick-Morning briefing"].exists)
        XCTAssertTrue(row.buttons["assistant-quick-Log caffeine"].exists)
        XCTAssertFalse(row.buttons["assistant-quick-How is my energy?"].exists)
        attachScreenshot("Next steps in the bottom row")
        curve.tap()
        XCTAssertTrue(app.staticTexts["Modeled alertness · 24 hours"].waitForExistence(timeout: 5))
        // The curve's own next steps replace the energy answer's; never itself.
        XCTAssertTrue(row.buttons["assistant-follow-up-energyCheckIn"].waitForExistence(timeout: 5))
        XCTAssertFalse(row.buttons["assistant-follow-up-energyProjection"].exists)
        XCTAssertEqual(row.buttons.count, 4)
    }

    /// The drink follow-up card from synthetic fixtures, for visual review.
    func testGalleryRepeatDrinkFixture() {
        app.terminate()
        app.launchArguments = ["-AuroraDesignGallery", "-AuroraGalleryExperience", "repeatDrink"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Aurora Design Gallery"].waitForExistence(timeout: 10))
        let title = cardTitle("repeatDrink")
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let review = app.buttons["repeat-drink-review"]
        for _ in 0..<12 where !review.isHittable { app.swipeUp() }
        XCTAssertTrue(review.isHittable)
        XCTAssertTrue(app.buttons["repeat-drink-dismiss"].exists)
        let question = NSPredicate(format: "label BEGINSWITH 'Did you have a Drip around ' AND label ENDSWITH '?'")
        XCTAssertTrue(app.staticTexts.matching(question).firstMatch.exists)
        attachScreenshot("Drink follow-up")
    }

    private func window() -> XCUIElement { app.windows.firstMatch }

    private func openGallery() {
        app.terminate(); app.launchArguments = ["-AuroraDesignGallery"]; app.launch()
        XCTAssertTrue(app.navigationBars["Aurora Design Gallery"].waitForExistence(timeout: 10))
    }

    /// Synthetic setup with failing saves shows the error and keeps the
    /// question; with saves working again the same Continue moves on.
    func testGallerySetupFixtureShowsSaveErrorThenRetries() {
        openGallery()
        let open = app.buttons["gallery-setup"]
        for _ in 0..<12 where !open.isHittable { app.swipeUp() }
        open.tap()
        let saving = app.segmentedControls["gallery-setup-saving"]
        XCTAssertTrue(saving.waitForExistence(timeout: 5))
        saving.buttons["Saves fail"].tap()
        let name = app.textFields["setup-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Sam")
        tapWhenReady(app.buttons["setup-next"])
        let failure = app.staticTexts["setup-save-failure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["setup-question-name"].exists)
        attachScreenshot("Setup save error")
        saving.buttons["Saves work"].tap()
        tapWhenReady(app.buttons["setup-next"])
        XCTAssertTrue(failure.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["setup-question-sleepTarget"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["setup-skip-all"].exists)
        attachScreenshot("Setup retry succeeded")
        app.buttons["gallery-setup-done"].tap()
    }

    /// Working, stopped and failed processing light, moving and static.
    func testGalleryMotionFixtureEndsAndStaysStatic() {
        openGallery()
        let phase = app.segmentedControls["gallery-motion-phase"]
        for _ in 0..<16 where !phase.isHittable { app.swipeUp() }
        XCTAssertTrue(phase.isHittable)
        let preview = app.descendants(matching: .any)["gallery-motion-preview"].firstMatch
        phase.buttons["Working"].tap()
        XCTAssertTrue(preview.label.contains("light moves only while work runs"), preview.label)
        phase.buttons["Stopped"].tap()
        XCTAssertTrue(preview.label.contains("last frame fades out"), preview.label)
        phase.buttons["Failed"].tap()
        XCTAssertTrue(preview.label.contains("Failed"), preview.label)
        let still = app.switches["Static, as with Reduce Motion"]
        still.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        phase.buttons["Working"].tap()
        XCTAssertTrue(preview.label.contains("static light"), preview.label)
        attachScreenshot("Static processing light")
    }

}
