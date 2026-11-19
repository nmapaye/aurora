import Foundation

/// Decides testLongCardArrivesShowingItsStart's three-second wait from
/// successive checks of the card title. Pure Foundation, so the rule can be
/// replayed against recorded checks (LongCardWaitTests).
///
/// The rule (approved Nov 10): the app still gets three seconds to show the
/// title, but the clock starts when the first check returns an
/// accessibility snapshot. Time spent before the simulator returns any
/// snapshot is simulator latency, not app time (run 42908012931, iPhone:
/// the only check in the old window got no snapshot after a 2.39 s
/// hierarchy capture, so the test failed without ever seeing the app).
/// - A check passes when the snapshot has a finite, non-empty frame and the
///   title is hittable. It must finish within three seconds of the first
///   snapshot.
/// - A hittable title outside the space between the navigation bar and the
///   composer fails at once, as the assertions after the old wait did.
/// - No success within three seconds of the first snapshot fails.
/// - If no check ever returns a snapshot, it fails twenty seconds after the
///   wait starts (the same overall cap as TypingProgress), naming that.
struct LongCardWait {
    enum Verdict: Equatable {
        case shown
        case wrongPlace
        case timedOut
        case neverSnapshotted
    }

    struct Check {
        /// Seconds since the wait started.
        var start: TimeInterval
        /// When the snapshot returned, and its frame; nil if the check got
        /// no snapshot.
        var snapshot: (at: TimeInterval, frame: CGRect)?
        var hittable: Bool = false
        /// Bottom of the navigation bar and top of the composer, read only
        /// when the title is hittable.
        var barMaxY: CGFloat?
        var composerMinY: CGFloat?
        var end: TimeInterval
    }

    static let window: TimeInterval = 3
    static let noSnapshotCap: TimeInterval = 20

    /// When the first snapshot returned; the three seconds run from here.
    private(set) var clockStart: TimeInterval?
    private(set) var log: [String] = []

    var deadline: TimeInterval? { clockStart.map { $0 + Self.window } }

    /// - Returns: nil to keep checking, or the verdict.
    mutating func observe(_ check: Check) -> Verdict? {
        let at = String(format: "%.2f", check.start)
        let end = String(format: "%.2f", check.end)
        guard let snapshot = check.snapshot else {
            log.append("\(at)s no snapshot end \(end)s")
            if clockStart == nil, check.end >= Self.noSnapshotCap { return .neverSnapshotted }
            return expired(check.end)
        }
        if clockStart == nil { clockStart = snapshot.at }
        let frame = snapshot.frame
        guard frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite, !frame.isEmpty else {
            log.append("\(at)s frame \(frame) end \(end)s")
            return expired(check.end)
        }
        log.append("\(at)s frame \(frame) hittable \(check.hittable) end \(end)s")
        guard check.hittable else { return expired(check.end) }
        if let deadline, check.end > deadline { return .timedOut }
        if let bar = check.barMaxY, frame.minY < bar - 1 { return .wrongPlace }
        if let composer = check.composerMinY, frame.maxY > composer { return .wrongPlace }
        return .shown
    }

    private func expired(_ now: TimeInterval) -> Verdict? {
        if let deadline, now >= deadline { return .timedOut }
        return nil
    }

    func describe(_ verdict: Verdict?) -> String {
        let clock = clockStart.map { String(format: "first snapshot at %.2f s", $0) } ?? "no snapshot returned"
        return "\(verdict.map { "\($0)" } ?? "undecided"); \(clock); checks: \(log)"
    }
}
