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
    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: timeout), .completed)
        element.tap()
    }
    private func tapQuick(_ label: String) {
        let button = app.buttons["assistant-quick-" + label]
        let strip = app.scrollViews["assistant-quick-actions"]
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
    func testAppleHealthConnectionIsReachableWithoutRequestingAccess() {
        finishSetup()
        tapQuick("Connect Apple Health")
        XCTAssertTrue(app.staticTexts["assistant-health-disclosure"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assistant-health-connect"].exists)
        app.buttons["assistant-health-done"].tap()
        XCTAssertTrue(app.buttons["assistant-send"].waitForExistence(timeout: 5))
    }

    func testHealthChoicesRemainReachableAtLargestTextWithoutRequestingAccess() {
        app.terminate()
        app.launchArguments = ["-AuroraUITestReset", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        finishSetup()
        tapQuick("Connect Apple Health")
        XCTAssertTrue(app.staticTexts["assistant-health-disclosure"].waitForExistence(timeout: 5))
        let titles = ["readSleep": "Read sleep", "readCaffeine": "Read caffeine", "writeCaffeine": "Add my caffeine to Health", "backgroundUpdates": "Update in the background"]
        for choice in ["readSleep", "readCaffeine", "writeCaffeine", "backgroundUpdates"] {
            let control = app.switches["assistant-health-" + choice]
            XCTAssertTrue(control.exists)
            // The stacked layout hides the visual title; the switch still announces it.
            XCTAssertEqual(control.label, titles[choice])
            func reachable() -> Bool {
                if control.isEnabled { return control.isHittable }
                return app.frame.contains(control.frame) && control.frame.minY > app.frame.minY + 100
            }
            for _ in 0..<12 where !reachable() { app.swipeUp() }
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
        tapWhenReady(app.buttons["setup-skip"])
        XCTAssertTrue(app.staticTexts["setup-question-calendar"].waitForExistence(timeout: 5))
        tapWhenReady(app.buttons["setup-skip"])
        tapWhenReady(app.buttons["setup-finish"])
        XCTAssertTrue(app.buttons["assistant-send"].waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.staticTexts["Unavailable"].exists)
    }
    func testEnergyCurveShowsModeledLabelsWithoutRecords() {
        finishSetup()
        tapQuick("Show my energy curve")
        XCTAssertTrue(app.staticTexts["Modeled alertness · 24 hours"].waitForExistence(timeout: 5))
        let curve = app.otherElements["assistant-energy-curve"]
        XCTAssertTrue(curve.waitForExistence(timeout: 5))
        XCTAssertTrue(curve.label.contains("Modeled, not measured"))
        XCTAssertTrue(app.staticTexts["No sleep or caffeine recorded in this window."].exists)
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
        save.tap()
        XCTAssertTrue(app.staticTexts["assistant-error"].waitForExistence(timeout: 3))
        amount.tap(); amount.typeText("120")
        let source = app.textFields["assistant-dose-source"]
        source.tap(); source.typeText("Tea")
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
        let quick = app.buttons["assistant-quick-Log sleep"]
        app.buttons["assistant-quick-Log caffeine"].tap()
        let amount = app.textFields["assistant-dose-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        let source = app.textFields["assistant-dose-source"]
        source.tap(); source.typeText("Tea")
        // End on the numeric pad, which has no Return key to dismiss it.
        amount.tap(); amount.typeText("80")
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
        XCTAssertTrue(app.buttons["Caffeine history"].waitForExistence(timeout: 5))
        app.buttons["Caffeine history"].tap()
        XCTAssertTrue(app.navigationBars["Caffeine History"].waitForExistence(timeout: 5))
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
        app.buttons["assistant-quick-Log sleep"].tap()
        let save = app.buttons["assistant-sleep-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        app.swipeUp()
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
        XCTAssertTrue(app.switches["Proactive suggestions"].waitForExistence(timeout: 5))
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
        finishSetup(); request("Morning briefing")
        XCTAssertTrue(app.staticTexts["Your recorded day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["assistant-composer"].isHittable)
        XCTAssertTrue(app.buttons["assistant-send"].exists)
        request("Reminders")
        let reminder = app.switches["Cutoff reminder"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        for _ in 0..<4 where !reminder.isHittable { app.swipeUp() }
        XCTAssertTrue(reminder.isHittable)
    }

}
