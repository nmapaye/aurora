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

    /// Run 43934444680, iPad iteration 35: the first check got its snapshot
    /// at 1.10 s with the title hittable and in place (frame, bar bottom
    /// y=65 and composer top y=1307 from the run's dump), but the bar and
    /// composer reads after it ran the check to 5.14 s, past the 4.10 s
    /// deadline. The log didn't record when isHittable returned; 1.30 s is
    /// constructed. The placement reads aren't app time, so this is shown.
    func testSlowPlacementReadsAfterAPromptHittableAnswerPass() {
        let frame = CGRect(x: 234, y: 617.5, width: 259.5, height: 20.5)
        let check = Check(start: 0.0, snapshot: (1.10, frame), hittable: true, hittableAt: 1.30,
                          barMaxY: 65, composerMinY: 1307, end: 5.14)
        let (verdict, wait) = run([check])
        XCTAssertEqual(verdict, .shown, wait.describe(verdict))
        XCTAssertTrue(wait.describe(verdict).contains("hittable true at 1.30s end 5.14s"))
    }

    /// Run 44450057420 on main (ec697957, iPad long-card repeat): the same
    /// shape on main. "first snapshot at 0.95 s; checks: 0.00s frame (234.0,
    /// 617.5, 259.5, 20.5) hittable true end 4.46s" was reported as timedOut
    /// against the 3.95 s deadline. Bar and composer are the iPad values
    /// above; 1.15 s for the hittability answer is constructed.
    func testMainRun44450057420FirstCheckHittableIsShown() {
        let frame = CGRect(x: 234, y: 617.5, width: 259.5, height: 20.5)
        let check = Check(start: 0.0, snapshot: (0.95, frame), hittable: true, hittableAt: 1.15,
                          barMaxY: 65, composerMinY: 1307, end: 4.46)
        let (verdict, wait) = run([check])
        XCTAssertEqual(verdict, .shown, wait.describe(verdict))
    }

    /// The hittability answer itself arriving after the deadline still
    /// fails, however fast the placement reads are.
    func testHittableAnswerPastTheDeadlineFails() {
        let checks = [seen(0.5, at: 1.0, top, hittable: false, 1.1),
                      Check(start: 3.8, snapshot: (3.9, top), hittable: true, hittableAt: 4.05,
                            barMaxY: bar, composerMinY: composer, end: 4.06)]
        XCTAssertEqual(run(checks).0, .timedOut)
    }

    /// Slow placement reads don't excuse a title in the wrong place.
    func testSlowPlacementReadsStillCatchAWrongPlace() {
        let hidden = CGRect(x: 38, y: 40, width: 259.3, height: 20.3)
        let check = Check(start: 0.0, snapshot: (1.10, hidden), hittable: true, hittableAt: 1.30,
                          barMaxY: bar, composerMinY: composer, end: 5.14)
        XCTAssertEqual(run([check]).0, .wrongPlace)
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
