import XCTest

/// Replays title checks through testLongCardArrivesShowingItsStart's wait.
/// These tests don't launch the app. Times are seconds after the wait
/// started. Only the 1.05 s "no snapshot" check is from CI (run 42908012931,
/// iPhone iteration 19); the other timings are constructed cases.
final class LongCardWaitTests: XCTestCase {
    typealias Check = LongCardWait.Check

    /// Title at the top, under a bar ending at y=100, composer at y=791
    /// (the frame from the run's final dump).
    private let top = CGRect(x: 38, y: 132, width: 259.3, height: 20.3)
    private let bar: CGFloat = 100
    private let composer: CGFloat = 791

    private func none(_ start: TimeInterval, _ end: TimeInterval) -> Check {
        Check(start: start, snapshot: nil, end: end)
    }
    private func seen(_ start: TimeInterval, at: TimeInterval, _ frame: CGRect, hittable: Bool, _ end: TimeInterval) -> Check {
        Check(start: start, snapshot: (at, frame), hittable: hittable,
              barMaxY: hittable ? bar : nil, composerMinY: hittable ? composer : nil, end: end)
    }

    private func run(_ checks: [Check]) -> (LongCardWait.Verdict?, LongCardWait) {
        var wait = LongCardWait()
        for check in checks {
            if let verdict = wait.observe(check) { return (verdict, wait) }
        }
        return (nil, wait)
    }

    /// The rule before this change: XCTWaiter(timeout: 3) from the start of
    /// the wait; only a hittable check that ends by 3 s satisfies it, and the
    /// placement asserts run after it.
    private func oldRule(_ checks: [Check]) -> LongCardWait.Verdict {
        guard let ok = checks.first(where: { $0.end <= 3 && $0.hittable && $0.snapshot != nil }) else { return .timedOut }
        let frame = ok.snapshot!.frame
        if let b = ok.barMaxY, frame.minY < b - 1 { return .wrongPlace }
        if let c = ok.composerMinY, frame.maxY > c { return .wrongPlace }
        return .shown
    }

    /// The first snapshot only returns at 2.39 s (not yet hittable); the
    /// title is hittable and in place at 3.4 s, 1.01 s of app time later.
    private var lateFirstSnapshot: [Check] {
        [seen(0.0, at: 2.39, top, hittable: false, 2.40),
         seen(2.50, at: 2.55, top, hittable: false, 2.60),
         seen(3.35, at: 3.38, top, hittable: true, 3.40)]
    }

    func testLateFirstSnapshotFailedTheOldRule() {
        XCTAssertEqual(oldRule(lateFirstSnapshot), .timedOut)
    }

    func testLateFirstSnapshotIsShownUnderTheNewRule() {
        let (verdict, wait) = run(lateFirstSnapshot)
        XCTAssertEqual(verdict, .shown, wait.describe(verdict))
        XCTAssertEqual(wait.clockStart, 2.39)
    }

    /// Iteration 19: the one check started at 1.05 s and got no snapshot.
    /// Later checks that do return a correct title must not be charged for it.
    func testNoSnapshotFirstThenShownPasses() {
        let checks = [none(1.05, 3.44), seen(3.55, at: 3.60, top, hittable: true, 3.65)]
        XCTAssertEqual(oldRule(checks), .timedOut)
        XCTAssertEqual(run(checks).0, .shown)
    }

    /// A correct title on the first check passes under both rules.
    func testPromptTitlePassesBothRules() {
        let checks = [seen(0.0, at: 0.06, top, hittable: true, 0.10)]
        XCTAssertEqual(oldRule(checks), .shown)
        XCTAssertEqual(run(checks).0, .shown)
    }

    /// Snapshots keep coming but the title is never hittable: it fails at
    /// the first check ending 3 s after the first snapshot, not later.
    func testNeverHittableFailsThreeSecondsAfterTheFirstSnapshot() {
        let checks = stride(from: 1.0, through: 10, by: 0.2).map {
            seen($0, at: $0 + 0.05, top, hittable: false, $0 + 0.1)
        }
        let (verdict, wait) = run(checks)
        XCTAssertEqual(verdict, .timedOut)
        XCTAssertEqual(wait.deadline, 1.05 + LongCardWait.window)
    }

    /// Hittable, but only after the three seconds from the first snapshot.
    func testHittableJustAfterTheWindowFails() {
        let checks = [seen(0.5, at: 1.0, top, hittable: false, 1.1),
                      seen(3.9, at: 4.0, top, hittable: true, 4.05)]
        XCTAssertEqual(run(checks).0, .timedOut)
    }

    /// The hittability round trip itself ending past the deadline still fails.
    func testHittableCheckEndingPastTheDeadlineFails() {
        let checks = [seen(0.5, at: 1.0, top, hittable: false, 1.1),
                      seen(3.8, at: 3.9, top, hittable: true, 4.2)]
        XCTAssertEqual(run(checks).0, .timedOut)
    }

    /// A title scrolled under the bar (the card showing its end) fails at
    /// once, under both rules.
    func testTitleUnderTheBarFails() {
        let hidden = CGRect(x: 38, y: 40, width: 259.3, height: 20.3)
        let checks = [seen(0.0, at: 0.06, hidden, hittable: true, 0.1)]
        XCTAssertEqual(oldRule(checks), .wrongPlace)
        XCTAssertEqual(run(checks).0, .wrongPlace)
        let late = [none(0.0, 2.9), seen(3.0, at: 3.1, hidden, hittable: true, 3.2)]
        XCTAssertEqual(run(late).0, .wrongPlace)
    }

    /// A title below the composer's top also fails.
    func testTitleBelowTheComposerFails() {
        let low = CGRect(x: 38, y: 780, width: 259.3, height: 20.3)
        XCTAssertEqual(run([seen(0.0, at: 0.06, low, hittable: true, 0.1)]).0, .wrongPlace)
    }

    /// An infinite or empty frame starts the clock (a snapshot returned) but
    /// is never a pass.
    func testUnusableFrameStartsTheClockButNeverPasses() {
        let infinite = CGRect(x: CGFloat.infinity, y: 0, width: 0, height: 0)
        let checks = stride(from: 0.5, through: 6, by: 0.25).map {
            seen($0, at: $0 + 0.05, infinite, hittable: true, $0 + 0.1)
        }
        let (verdict, wait) = run(checks)
        XCTAssertEqual(verdict, .timedOut)
        XCTAssertEqual(wait.clockStart, 0.55)
    }

    /// No snapshot ever: fails at the 20 s cap and says so.
    func testNoSnapshotEverFailsAtTheCap() {
        let checks = stride(from: 0.0, through: 30, by: 1).map { none($0, $0 + 0.5) }
        let (verdict, wait) = run(checks)
        XCTAssertEqual(verdict, .neverSnapshotted)
        XCTAssertTrue(wait.describe(verdict).contains("no snapshot returned"))
    }
}
