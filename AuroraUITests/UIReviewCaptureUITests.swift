import XCTest

/// Screenshots and accessibility trees for a UI review, not assertions.
/// Cards come from the Design Gallery's synthetic fixtures; flows start from
/// a reset so no personal records appear. Appearance comes from the
/// simulator (`simctl ui … appearance`); text size from the method.
final class UIReviewCaptureUITests: XCTestCase {
    private var app: XCUIApplication!
    private var label = ""

    override func setUpWithError() throws { continueAfterFailure = true }

    private static let largest = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(label) · \(name)"; shot.lifetime = .keepAlways
        add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(label) · \(name) · tree"; tree.lifetime = .keepAlways
        add(tree)
    }

    private func launch(_ arguments: [String]) {
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
    }

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 8) {
        guard element.waitForExistence(timeout: timeout) else { return }
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        if element.isHittable { element.tap() }
    }

    private func settle() { _ = app.wait(for: .runningForeground, timeout: 2); Thread.sleep(forTimeInterval: 0.8) }

    // MARK: Cards

    private static let kinds = ["welcome", "capabilities", "clarification", "caffeineDraft", "sleepDraft", "energy", "energyProjection", "energyCheckIn",
                                "cutoffScenario", "trends", "calendar", "reaction", "history", "exports", "briefing", "reminders",
                                "repeatDrink", "receipt"]

    private func cards(_ extra: [String]) {
        for kind in Self.kinds {
            launch(["-AuroraDesignGallery", "-AuroraGalleryExperience", kind] + extra)
            guard app.navigationBars["Aurora Design Gallery"].waitForExistence(timeout: 15) else { continue }
            let title = app.descendants(matching: .any)["assistant-card-\(kind)"].firstMatch
            if title.waitForExistence(timeout: 8) {
                for _ in 0..<14 where title.frame.minY > app.windows.firstMatch.frame.height * 0.25 { app.swipeUp() }
            }
            settle(); capture("card \(kind) · start")
            app.swipeUp(); settle(); capture("card \(kind) · more")
            app.terminate()
        }
    }

    func testCardsDefault() { label = "default"; cards([]) }
    func testCardsLargest() { label = "largest"; cards(Self.largest) }

    // MARK: First run and conversation

    private func flows(_ extra: [String]) {
        launch(["-AuroraUITestReset"] + extra)
        if app.buttons["onboarding-skip-story"].waitForExistence(timeout: 15) {
            settle(); capture("onboarding · story")
            app.buttons["onboarding-skip-story"].tap()
        }
        if app.buttons["setup-skip-all"].waitForExistence(timeout: 8) {
            settle(); capture("setup · first question")
            app.buttons["setup-skip-all"].tap()
        }
        if app.buttons["setup-finish"].waitForExistence(timeout: 8) {
            settle(); capture("setup · finish")
            app.buttons["setup-finish"].tap()
        }
        let composer = app.textFields["assistant-composer"]
        guard composer.waitForExistence(timeout: 15) else { capture("conversation · not reached"); return }
        settle(); capture("conversation · new")

        tap(app.buttons["assistant-quick-How is my energy?"])
        settle(); capture("conversation · energy answer and next steps")

        composer.tap(); composer.typeText("cut")
        settle(); capture("conversation · typed suggestions")
        if let typed = composer.value as? String, !typed.isEmpty {
            composer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        }
        app.swipeDown()

        tap(app.buttons["assistant-quick-Log caffeine"])
        let amount = app.textFields["assistant-dose-amount"]
        if amount.waitForExistence(timeout: 8) {
            settle(); capture("conversation · caffeine draft")
            amount.tap(); settle(); capture("conversation · caffeine draft with keyboard")
            app.swipeDown()
        }
        composer.tap(); composer.typeText("Log sleep")
        app.buttons["assistant-send"].tap()
        settle(); capture("conversation · sleep draft")

        composer.tap(); composer.typeText("Reminders")
        app.buttons["assistant-send"].tap()
        settle(); capture("conversation · reminders card")
        app.terminate()

        launch(["-AuroraUITestReset", "-AuroraUITestLongConversation"] + extra)
        tap(app.buttons["onboarding-skip-story"], timeout: 10)
        tap(app.buttons["setup-skip-all"])
        tap(app.buttons["setup-finish"])
        let earlier = app.buttons["assistant-show-earlier"]
        for _ in 0..<20 where !earlier.exists || !earlier.isHittable { app.swipeDown() }
        settle(); capture("conversation · show earlier messages")
        app.terminate()
    }

    func testFlowsDefault() { label = "default"; flows([]) }
    func testFlowsLargest() { label = "largest"; flows(Self.largest) }

    // MARK: Settings and tools

    private func settings(_ extra: [String]) {
        launch(["-AuroraUITestReset"] + extra)
        tap(app.buttons["onboarding-skip-story"], timeout: 15)
        tap(app.buttons["setup-skip-all"])
        tap(app.buttons["setup-finish"])
        tap(app.buttons["assistant-settings"], timeout: 15)
        settle(); capture("settings · top")
        for page in 1...4 { app.swipeUp(); settle(); capture("settings · page \(page)") }
        app.swipeDown(velocity: .fast)
        if app.buttons["Done"].exists { app.buttons["Done"].tap() } else { app.swipeDown(velocity: .fast) }
        tap(app.buttons["assistant-history"], timeout: 8)
        settle(); capture("history and tools · top")
        app.swipeUp(); settle(); capture("history and tools · more")
        app.terminate()

        launch(["-AuroraDesignGallery"] + extra)
        if app.navigationBars["Aurora Design Gallery"].waitForExistence(timeout: 15) {
            tap(app.buttons["gallery-health-choices"])
            settle(); capture("health connection")
            app.swipeUp(); settle(); capture("health connection · more")
        }
        app.terminate()
    }

    func testSettingsDefault() { label = "default"; settings([]) }
    func testSettingsLargest() { label = "largest"; settings(Self.largest) }
}
