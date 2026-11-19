import XCTest

/// Taps Send until the request leaves the composer, up to three times.
///
/// The keyboard can still be moving the composer when the first tap lands,
/// so a retry is needed. A retry must never land on a disabled Send (empty
/// field after a send) or on Stop (still working): a tap there falls through
/// to the composer surface, focuses the field and raises the keyboard over
/// the answer (run 42862394439).
///
/// Every check reads the element directly. The earlier version waited on an
/// `NSPredicate` block through `XCTNSPredicateExpectation`; it never
/// reported the disabled Send (the failure snapshot shows Send `Disabled`
/// after three taps), so each retry focused the composer.
enum SendRetry {
    static func send(text: String, input: XCUIElement, send: XCUIElement, settle: TimeInterval) {
        for attempt in 0..<3 {
            if attempt > 0 {
                // Re-tap only when the request is still in the field and
                // Send can take it.
                guard send.exists, send.isEnabled, (input.value as? String) == text else { return }
            }
            send.tap()
            if poll(timeout: settle, { (input.value as? String) != text }) { return }
            if poll(timeout: 1, { !send.exists || !send.isEnabled }) { return }
        }
    }

    /// Checks `condition` now and every 0.1 s until it holds or `timeout`
    /// passes; true when it held.
    static func poll(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while true {
            if condition() { return true }
            if Date() >= end { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}
