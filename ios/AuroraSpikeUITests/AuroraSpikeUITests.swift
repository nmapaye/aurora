import XCTest

final class AuroraSpikeUITests: XCTestCase {
    @MainActor
    func testConfiguredFavoriteAndPartialServing() throws {
        let app = XCUIApplication()
        app.launch()
        let favorite = app.buttons["favorite-tumbler"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 15))
        keepScreenshot("Today")
        favorite.tap()
        let log = app.buttons["log-serving"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        XCTAssertFalse(log.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["drink-fill"].firstMatch.exists)
        app.buttons["2 shots"].tap()
        XCTAssertTrue(log.isEnabled)
        XCTAssertEqual(app.staticTexts["serving-caffeine-estimate"].label, "120 mg")
        keepScreenshot("Full tumbler with two shots")
        app.buttons["½"].tap()
        XCTAssertEqual(app.staticTexts["serving-caffeine-estimate"].label, "60 mg")
        keepScreenshot("Half tumbler with two shots")
        log.tap()
        let undo = app.buttons["undo-dose"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertFalse(undo.exists)
        favorite.tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertFalse(log.exists, "A configured favorite should log without reopening the serving sheet.")
        keepScreenshot("One tap repeat with Undo")
    }

    @MainActor
    func testSleepEditorIsReachable() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["favorite-tumbler"].waitForExistence(timeout: 15))
        if app.tabBars.buttons["Sleep"].exists {
            app.tabBars.buttons["Sleep"].tap()
        } else if app.buttons["Sleep"].firstMatch.exists {
            app.buttons["Sleep"].firstMatch.tap()
        } else {
            app.staticTexts["Sleep"].firstMatch.tap()
        }
        let edit = app.buttons["edit-sleep-plan"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.buttons["accept-sleep-plan"].waitForExistence(timeout: 5))
        keepScreenshot("Sleep time editor")
        app.buttons["accept-sleep-plan"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        keepScreenshot("Accepted sleep window")
    }

    @MainActor
    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
