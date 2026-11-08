import Foundation

/// A transient request to OPEN the existing manual review, never to save a dose.
/// Contains no drink fields, personal text, persistence or Health/model operation.
public struct CaffeineReviewShortcut: Sendable {
    public private(set) var requested = false
    public init() {}
    public mutating func request() { requested = true }
    public mutating func cancel() { requested = false }

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
