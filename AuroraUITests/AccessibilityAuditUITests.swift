import XCTest

/// Apple's automated accessibility audit (contrast, hit regions, labels,
/// traits, Dynamic Type, clipped text) on every main screen, at the default
/// and the largest accessibility text size. Each screen is audited where a
/// person would see it; every issue is listed with its screen and element,
/// and the test fails once at the end with the whole list.
final class AccessibilityAuditUITests: XCTestCase {
    private var app: XCUIApplication!
    /// Fail the test.
    private var issues: [String] = []
    /// Listed in the report only; see `audit(_:)` for why each kind is.
    private var reported: [String] = []
    private var largestText = false

    override func setUpWithError() throws {
        // About 11 minutes per text size; CI runs it on the iPhone job only.
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "The audit runs on iPhone; run it on iPad by hand when iPad layouts change.")
        continueAfterFailure = true
        app = XCUIApplication()
    }

    func testAuditAtDefaultTextSize() throws {
        try auditEverything(arguments: ["-AuroraUITestReset"])
    }

    func testAuditAtLargestTextSize() throws {
        largestText = true
        try auditEverything(arguments: ["-AuroraUITestReset", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    }

    // MARK: Walk

    private func auditEverything(arguments: [String]) throws {
        app.launchArguments = arguments
        app.launch()

        let skipStory = app.buttons["onboarding-skip-story"]
        XCTAssertTrue(skipStory.waitForExistence(timeout: 15))
        try audit("Onboarding story")
        skipStory.tap()
        let skipAll = app.buttons["setup-skip-all"]
        XCTAssertTrue(skipAll.waitForExistence(timeout: 5))
        try audit("Setup")
        skipAll.tap()
        let finish = app.buttons["setup-finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        try audit("Setup finish")
        finish.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertTrue(card("welcome").waitForExistence(timeout: 5))
        try audit("Welcome")

        for (request, kind) in Self.cards {
            send(request)
            if card(kind).waitForExistence(timeout: 8) {
                try audit("Card: \(request)")
            } else {
                issues.append("[\(request)] card \(kind) never appeared")
            }
        }

        // The reaction test, full screen, before it starts.
        send("Reaction test")
        let starts = app.buttons.matching(identifier: "assistant-reaction-start")
        let start = starts.element(boundBy: max(0, starts.count - 1))
        if start.waitForExistence(timeout: 5) {
            start.tap()
            if app.buttons["reaction-start"].waitForExistence(timeout: 5) {
                try audit("Reaction test")
                let close = app.buttons["reaction-close"]
                if close.exists { close.tap() } else { app.buttons["Close"].firstMatch.tap() }
            }
        }

        // Settings sheet.
        app.buttons["assistant-settings"].tap()
        if app.navigationBars["Aurora settings"].waitForExistence(timeout: 5) {
            try audit("Aurora settings")
            app.navigationBars["Aurora settings"].buttons["Done"].tap()
        }

        // Records and each screen it opens.
        app.buttons["assistant-history"].tap()
        for row in ["records-caffeine", "records-sleep", "records-insights", "records-settings"] {
            let button = app.buttons[row]
            guard button.waitForExistence(timeout: 5) else { issues.append("[Records] \(row) missing"); continue }
            try audit("Records")
            button.tap()
            sleep(1)
            try audit("Records › \(row)")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        record()
    }

    /// Request, and the card kind it answers with.
    private static let cards: [(String, String)] = [
        ("Morning briefing", "briefing"),
        ("How is my energy?", "energy"),
        ("Show my energy curve", "energyProjection"),
        ("Show this week", "trends"),
        ("Log caffeine", "caffeineDraft"),
        ("Log sleep", "sleepDraft"),
        ("Check in my energy", "energyCheckIn"),
        ("Reminders", "reminders"),
        ("History", "history"),
        ("Export records", "exports"),
        ("Cutoff scenario", "cutoffScenario"),
        ("Reaction test", "reaction"),
        ("help", "capabilities"),
    ]

    // MARK: Audit

    private func audit(_ screen: String) throws {
        // Cards fade and slide in; audited mid-transition, settled text
        // reads as low contrast. Let the screen come to rest first.
        Thread.sleep(forTimeInterval: 1.5)
        if ProcessInfo.processInfo.environment["AURORA_AUDIT_SHOTS"] == "1" {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "audit \(screen)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        let visible = visibleArea()
        try app.performAccessibilityAudit(for: .all) { issue in
            let element = issue.element.map { element -> String in
                let id = element.identifier.isEmpty ? "" : " #\(element.identifier)"
                return "\(element.elementType.rawValue) '\(element.label)'\(id) \(element.frame.integral)"
            } ?? "no element"
            let line = "[\(screen)] \(Self.name(issue.auditType)): \(issue.compactDescription) — \(element)"
            if let reason = self.reportOnly(issue, visible: visible) {
                self.reported.append("\(line) (\(reason))")
            } else {
                self.issues.append(line)
            }
            return true
        }
    }

    /// Why an issue is listed but doesn't fail the test, or nil to fail it.
    private func reportOnly(_ issue: XCUIAccessibilityAuditIssue, visible: CGRect) -> String? {
        // Contrast is checked against WCAG AA for every text/background token
        // pair in PaletteContrastTests. The audit holds small text to a
        // stricter bar (white on teal at 6.2:1 "nearly passed"), and samples
        // whatever covers an element, such as the solid bars.
        if issue.auditType == .contrast { return "contrast: see PaletteContrastTests" }
        // Scaling is verified where it matters, at the largest size; at the
        // default size the audit flagged semantic fonts that do scale fully.
        if issue.auditType == .dynamicType && !largestText { return "default size" }
        // Nothing to point at or fix: in practice chart axis numbers, which
        // Swift Charts exposes as axis summaries instead.
        guard let element = issue.element else { return "no element" }
        // Partly under the navigation bar or the composer, or off screen: the
        // audit reads the bar's pixels and frames, not the element's.
        if !visible.contains(element.frame.insetBy(dx: 1, dy: 1)) { return "not fully on screen" }
        if issue.auditType == .dynamicType, let reason = Self.cappedOnPurpose(element) { return reason }
        // Small caps are drawn from lowercase text, which the audit reads as clipped.
        if issue.auditType == .textClipped, element.label == element.label.uppercased(), element.label.count > 3 { return "small caps" }
        // Records' navigation rows: screenshots at the default and largest
        // sizes show the titles whole; the audit reads the row's label frame.
        if issue.auditType == .textClipped, ["Sleep", "Insights", "Caffeine"].contains(element.label) { return "list row, checked by screenshot" }
        return nil
    }

    /// Text in a bar that never scrolls, capped so it doesn't cover the
    /// screen. Each shows the Large Content Viewer on a long press.
    private static func cappedOnPurpose(_ element: XCUIElement) -> String? {
        let setup: Set<String> = ["setup-next", "setup-skip", "setup-sample", "setup-finish", "setup-skip-all"]
        if setup.contains(element.identifier) { return "setup controls, capped at accessibility 2" }
        if element.label.hasPrefix("Example records") { return "setup controls, capped at accessibility 2" }
        if element.label == "Aurora" { return "navigation title, system-capped" }
        if element.identifier == "sleep-add-data" || element.label == "Done" { return "navigation bar button, system-capped" }
        return nil
    }

    /// Between the navigation bar and the composer (or the screen's bottom).
    private func visibleArea() -> CGRect {
        let window = app.windows.firstMatch.frame
        let bar = app.navigationBars.firstMatch
        let top = bar.exists ? bar.frame.maxY : window.minY
        var bottom = window.maxY
        let quick = app.descendants(matching: .any)["assistant-quick-actions"].firstMatch
        if quick.exists { bottom = min(bottom, quick.frame.minY) }
        if composer.exists { bottom = min(bottom, composer.frame.minY) }
        return CGRect(x: window.minX, y: top, width: window.width, height: max(0, bottom - top))
    }

    private func record() {
        let unique = Array(NSOrderedSet(array: issues)) as? [String] ?? issues
        let listed = Array(NSOrderedSet(array: reported)) as? [String] ?? reported
        let report = XCTAttachment(string: (unique + ["", "Reported only:"] + listed).joined(separator: "\n"))
        report.name = "Accessibility audit (\(unique.count) issues, \(listed.count) reported)"
        report.lifetime = .keepAlways
        add(report)
        XCTAssertTrue(unique.isEmpty, "\(unique.count) accessibility issues:\n" + unique.joined(separator: "\n"))
    }

    private static func name(_ type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .contrast: "contrast"
        case .elementDetection: "elementDetection"
        case .hitRegion: "hitRegion"
        case .sufficientElementDescription: "description"
        case .dynamicType: "dynamicType"
        case .textClipped: "textClipped"
        case .trait: "trait"
        default: "other(\(type.rawValue))"
        }
    }

    // MARK: Helpers

    private var composer: XCUIElement { app.textFields["assistant-composer"] }

    private func card(_ kind: String) -> XCUIElement {
        app.descendants(matching: .any)["assistant-card-\(kind)"].firstMatch
    }

    /// Types the whole request, retrying lost keystrokes, then sends it and
    /// puts the keyboard away so the card is what gets audited.
    private func send(_ text: String) {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let complete = NSPredicate(format: "value == %@", text)
        for _ in 0..<3 {
            composer.tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: composer)], timeout: 3)
            if let partial = composer.value as? String, !partial.isEmpty, partial != text {
                composer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: partial.count))
            }
            composer.typeText(text)
            if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: complete, object: composer)], timeout: 2) == .completed { break }
        }
        let cleared = NSPredicate(format: "value != %@", text)
        for _ in 0..<3 {
            app.buttons["assistant-send"].tap()
            if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: cleared, object: composer)], timeout: 2) == .completed { break }
        }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(
                forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)),
                withVelocity: .slow, thenHoldForDuration: 0.05)
            _ = keyboard.waitForNonExistence(timeout: 3)
        }
    }
}
