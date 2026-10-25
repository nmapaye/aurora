import XCTest

// Run only against an optimized Release build on a fresh, disposable simulator.
// No Debug reset/gallery launch arguments or permission fixtures are available.
#if !DEBUG
final class ReleaseSmokeUITests: XCTestCase {
    func testCleanInstallOnboardingRelaunchAndBackgroundReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()

        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 15))
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            element.tap()
        }
        tap(app.buttons["onboarding-skip-story"])
        tap(app.buttons["setup-skip-all"])
        tap(app.buttons["setup-finish"])
        XCTAssertTrue(app.textFields["assistant-composer"].waitForExistence(timeout: 15))
        tap(app.buttons["assistant-quick-How is my energy?"])
        XCTAssertTrue(app.descendants(matching: .any)["assistant-card-energy"].firstMatch.waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["assistant-composer"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["onboarding-skip-story"].exists, "Completed setup must survive a Release relaunch")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.textFields["assistant-composer"].waitForExistence(timeout: 15))
        let history = app.buttons["assistant-history"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: history)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Release clean install, persisted setup and background return"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
#endif
