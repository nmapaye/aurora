import Foundation

/// A transient request to OPEN the existing manual review, never to save a dose.
/// Review Drink carries no drink; Log Drink carries only the drink the person
/// chose, which prefills the review. No personal text, persistence or
/// Health/model operation; Save on the card is the only write.
public struct CaffeineReviewShortcut: Sendable {
    public private(set) var requested = false
    /// The Log Drink choice to prefill, kept until the next request or cancel.
    public private(set) var drink: LogDrinkShortcut.Choice?
    public init() {}
    public mutating func request(drink: LogDrinkShortcut.Choice? = nil) { requested = true; self.drink = drink }
    public mutating func cancel() { requested = false; drink = nil }

    /// Covering work consumes immediately, even before foreground/storage readiness.
    /// Otherwise wait for readiness and open exactly once, never after a blocked request.
    public mutating func consume(ready: Bool, hasOpenReview: Bool) -> Bool {
        guard requested else { return false }
        // Covering work wins even during background/storage transitions: consume
        // now, rather than opening a hidden review when that work is dismissed.
        if hasOpenReview { requested = false; return false }
        guard ready else { return false }
        requested = false
        return true
    }
}
