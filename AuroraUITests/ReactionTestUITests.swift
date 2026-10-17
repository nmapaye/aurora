import XCTest

/// Regression tests for touches the Reaction Test used to drop: it opened
/// as a sheet whose dismiss pan took short slides, timed taps at touch-up so
/// long presses failed, never saw two-finger touches, and left about 39% of
/// the screen inactive. Built from the touch-probe battery on
/// `claude/pvt-touch-investigation`.
///
/// `-AuroraReactionTestHoldCue` keeps the cue from ever appearing and the
/// run from ending, so every touch is an early tap, and shows a line with the
/// counts: "touches T early E ignored I".
final class ReactionTestUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AuroraUITestReset"] + (name.contains("Full30SecondRun") ? [] : ["-AuroraReactionTestHoldCue"])
        app.launch()
    }

    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(element)")
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: timeout), .completed)
        element.tap()
    }

    private func finishSetup() {
        tapWhenReady(app.buttons["onboarding-skip-story"], timeout: 15)
        tapWhenReady(app.buttons["setup-skip-all"])
        tapWhenReady(app.buttons["setup-finish"])
        XCTAssertTrue(app.textFields["assistant-composer"].waitForExistence(timeout: 10))
    }

    private func request(_ text: String) {
        let input = app.textFields["assistant-composer"]
        input.tap(); input.typeText(text)
        let cleared = NSPredicate(format: "value != %@", text)
        for _ in 0..<3 {
            app.buttons["assistant-send"].tap()
            if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: cleared, object: input)], timeout: 2) == .completed { break }
        }
    }

    /// Opens the test from the conversation card and starts a run.
    private func openFromTheCardAndStart() -> XCUIElement {
        finishSetup(); request("Reaction test")
        let open = app.buttons["assistant-reaction-start"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertEqual(open.label, "Start 30-second test")
        open.tap()
        attachScreenshot("reaction-instructions")
        tapWhenReady(app.buttons["reaction-start"])
        let area = app.descendants(matching: .any)["reaction-area"].firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 5))
        return area
    }

    private var diagnostics: XCUIElement { app.staticTexts["reaction-diagnostics"] }

    /// Kept for visual review; not an assertion.
    private func attachScreenshot(_ name: String) {
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = name
        capture.lifetime = .keepAlways
        add(capture)
    }

    private struct Counts: Equatable, CustomStringConvertible {
        var touches = 0, early = 0, ignored = 0
        var description: String { "touches \(touches) early \(early) ignored \(ignored)" }
    }

    private func counts() -> Counts {
        let words = diagnostics.label.split(separator: " ")
        guard words.count == 6, let t = Int(words[1]), let e = Int(words[3]), let i = Int(words[5]) else { return Counts(touches: -1) }
        return Counts(touches: t, early: e, ignored: i)
    }

    /// Waits for the counts to reach `want`; a touch ignored as the rest of a
    /// double tap would leave `early` short.
    private func expect(_ want: Counts, _ step: String, file: StaticString = #filePath, line: UInt = #line) {
        let reached = NSPredicate(format: "label == %@", want.description)
        // 6 s: on CI's iPad the right count once arrived just after a 3 s wait.
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: reached, object: diagnostics)], timeout: 6)
        XCTAssertEqual(result, .completed, "\(step): wanted \(want), got \(diagnostics.label)", file: file, line: line)
    }

    /// Leaves the double-tap window (300 ms) between separate gestures.
    private func settle() { Thread.sleep(forTimeInterval: 0.4) }

    /// Without touch: Space and Return on a hardware keyboard answer like a
    /// tap (Full Keyboard Access and Switch Control activate the area the
    /// same way). Escape ends the run as Close does, but the simulator
    /// doesn't deliver it to apps.
    func testKeyboardAnswersWithSpaceOrReturn() {
        _ = openFromTheCardAndStart()
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 3))
        var want = Counts()
        expect(want, "start")
        app.typeKey(" ", modifierFlags: [])
        want.touches += 1; want.early += 1
        expect(want, "space"); settle()
        // "\n" is the Return key's HID usage; XCUIKeyboardKey.return ("\r")
        // never reaches the app in the simulator.
        app.typeKey("\n", modifierFlags: [])
        want.touches += 1; want.early += 1
        expect(want, "return"); settle()
        // Other keys don't answer.
        app.typeKey("a", modifierFlags: [])
        settle()
        expect(want, "a letter")
    }

    func testTheTestFromTheCardIsFullScreenAndEveryTouchRegisters() {
        let area = openFromTheCardAndStart()
        // Full screen: the surface covers the window and the conversation
        // isn't reachable behind it.
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(area.frame.width, window.width, accuracy: 1)
        XCTAssertEqual(area.frame.height, window.height, accuracy: 1)
        XCTAssertFalse(app.textFields["assistant-composer"].isHittable)
        XCTAssertEqual(area.value as? String, "Wait for the cue")
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 3))
        var want = Counts()
        expect(want, "start")
        attachScreenshot("reaction-waiting")

        let origin = app.coordinate(withNormalizedOffset: .zero)
        func at(_ nx: CGFloat, _ ny: CGFloat) -> XCUICoordinate {
            origin.withOffset(CGVector(dx: window.minX + window.width * nx, dy: window.minY + window.height * ny))
        }
        let center = at(0.5, 0.5)

        center.tap()
        want.touches += 1; want.early += 1
        expect(want, "tap")
        attachScreenshot("reaction-too-early"); settle()

        // Slides that a sheet's dismiss pan used to take.
        for dy in [10.0, 15, 20, 30, -10, -20, -30] {
            center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 0, dy: dy)),
                         withVelocity: XCUIGestureVelocity(400), thenHoldForDuration: 0)
            want.touches += 1; want.early += 1
            expect(want, "slide \(dy) pt"); settle()
        }

        // Presses that a touch-up tap failed.
        for duration in [0.75, 1.0, 1.6] {
            center.press(forDuration: duration)
            want.touches += 1; want.early += 1
            expect(want, "press \(duration) s"); settle()
        }

        // Two fingers count once; a finger landing a moment later is ignored.
        for _ in 0..<2 {
            let before = counts()
            area.twoFingerTap()
            let reached = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let now = self.counts()
                return now.early == before.early + 1 && now.touches > before.touches
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [reached], timeout: 3), .completed, "two-finger tap: \(diagnostics.label)")
            settle()
            want = counts()
            XCTAssertEqual(want.touches - before.touches, 1 + (want.ignored - before.ignored), "two-finger tap: \(diagnostics.label)")
        }

        // A double tap counts once.
        center.doubleTap()
        want.touches += 2; want.early += 1; want.ignored += 1
        expect(want, "double tap"); settle()

        // The old inactive regions: under the header and countdown, beside
        // and below the old area, the summary tiles, the bottom padding.
        for (nx, ny) in [(0.5, 0.1), (0.85, 0.08), (0.03, 0.5), (0.97, 0.5), (0.5, 0.82), (0.2, 0.9), (0.8, 0.93), (0.03, 0.2)] {
            at(nx, ny).tap()
            want.touches += 1; want.early += 1
            expect(want, "region (\(nx), \(ny))"); settle()
        }
    }

    func testCloseMidTestAsksForConfirmation() {
        let area = openFromTheCardAndStart()
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 3))
        tapWhenReady(app.buttons["reaction-close"])
        let alert = app.alerts["End test?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        attachScreenshot("reaction-end-confirmation")
        XCTAssertTrue(alert.staticTexts["This run won’t be saved."].firstMatch.exists)
        XCTAssertTrue(alert.buttons["End"].firstMatch.exists)
        // Keep going returns to the same run, still taking touches.
        alert.buttons["Keep going"].firstMatch.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 3))
        XCTAssertTrue(area.exists)
        area.tap()
        expect(Counts(touches: 1, early: 1, ignored: 0), "after Keep going")
        settle()
        // End leaves without saving.
        tapWhenReady(app.buttons["reaction-close"])
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["End"].firstMatch.tap()
        XCTAssertTrue(area.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.textFields["assistant-composer"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Reaction Test recorded"].exists)
    }

    /// A real run: answers each cue as XCUITest sees it, so most responses
    /// are slow, and checks the run ends by itself and is saved.
    func testAFull30SecondRunEndsAndSaves() {
        let area = openFromTheCardAndStart()
        let complete = app.staticTexts["Session complete"]
        // A coordinate tap doesn't need the area to still exist when the run ends.
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let deadline = Date().addingTimeInterval(45)
        var answered = 0
        // Predicate expectations poll about once a second, slower than the
        // 1 s window, so read the value directly. `snapshot()` throws rather
        // than failing the test once the run ends and the surface is gone.
        while Date() < deadline && !complete.exists {
            if (try? area.snapshot())?.value as? String == "Tap now" {
                middle.tap()
                answered += 1
            }
        }
        XCTAssertTrue(complete.waitForExistence(timeout: 5), "answered \(answered)")
        XCTAssertGreaterThan(answered, 3)
        attachScreenshot("reaction-results")
        XCTAssertTrue(app.staticTexts["A quick check of reaction speed, not a medical assessment."].exists)
        tapWhenReady(app.buttons["Done"])
        XCTAssertTrue(app.staticTexts["Reaction Test recorded"].waitForExistence(timeout: 5))
    }
}
