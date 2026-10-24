import XCTest

/// Hardware keyboard: Return sends from the composer.
///
/// Escape is also wired (each sheet's Done or Cancel, and the Reaction
/// Test's Close), but the simulator never delivers XCUIKeyboardKey.escape
/// (or .return, "\r") to the app, so it can't be asserted here. Full
/// Keyboard Access reaches every control because each is a real control;
/// GestureOnlyControlTests keeps it that way.
final class KeyboardAccessUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AuroraUITestReset"]
        app.launch()
        tapWhenReady(app.buttons["onboarding-skip-story"], timeout: 15)
        tapWhenReady(app.buttons["setup-skip-all"])
        tapWhenReady(app.buttons["setup-finish"])
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
    }

    private var composer: XCUIElement { app.textFields["assistant-composer"] }

    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(element)")
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: timeout), .completed)
        element.tap()
    }

    func testReturnSendsFromTheComposer() {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        composer.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: composer)], timeout: 3), .completed)
        composer.typeText("help")
        // "\n" is the Return key's HID usage; XCUIKeyboardKey.return ("\r")
        // never reaches the app in the simulator.
        app.typeKey("\n", modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["assistant-card-capabilities"].firstMatch.waitForExistence(timeout: 5))
    }
}
