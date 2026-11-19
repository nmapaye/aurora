import XCTest

/// Replays composer reads through request()'s typing check. These tests
/// don't launch the app: each read is (start, value, end) in seconds after
/// typeText returned.
final class TypingProgressTests: XCTestCase {
    typealias Read = (start: TimeInterval, value: String?, end: TimeInterval)

    private func verdict(_ text: String, _ reads: [Read]) -> (TypingProgress.Verdict?, TypingProgress) {
        var progress = TypingProgress(text: text)
        for read in reads {
            if let verdict = progress.observe(read.value, readStart: read.start, readEnd: read.end) { return (verdict, progress) }
        }
        return (nil, progress)
    }

    /// The check before this change: one waitForExistence(timeout: 5)
    /// started 0.63 s after typeText returned (XCTest's idle wait). Only a
    /// read that ends inside that window can satisfy it.
    private func fixedWindow(_ text: String, _ reads: [Read], waitStart: TimeInterval = 0.63) -> Bool {
        reads.contains { $0.end <= waitStart + 5 && $0.value == text }
    }

    /// Run 42895134800, iPhone, long-card repeat iteration 5. The reads come
    /// from the app's AX server log (typeText returned 20:36:39.38Z):
    /// "Sh" (sent 41.055, answered 45.78 after the main run loop was blocked
    /// 4.6 s), "Show" (45.306 to 47.75), then the full text (48.297 to 48.339).
    private let iteration5: [Read] = [(1.67, "Sh", 6.40), (5.92, "Show", 8.37), (8.92, "Show this week", 8.96)]

    func testIteration5FailedTheFixedWindow() {
        XCTAssertFalse(fixedWindow("Show this week", iteration5))
    }

    func testIteration5CompletesWithProgress() {
        let (result, progress) = verdict("Show this week", iteration5)
        XCTAssertEqual(result, .complete)
        XCTAssertEqual(progress.lastSeen, "Show this week")
    }

    /// Iterations 1-4: the first read, about 1 s after typing, already
    /// shows the full text.
    func testFastTypingCompletesOnTheFirstRead() {
        let reads: [Read] = [(1.06, "Show this week", 1.12)]
        XCTAssertTrue(fixedWindow("Show this week", reads))
        XCTAssertEqual(verdict("Show this week", reads).0, .complete)
    }

    /// Lost keystrokes ("R" for "Reminders"): reads every 0.3 s never grow.
    /// It fails on the first read that starts 5 s after "R" was first seen,
    /// as fast as the old fixed window did.
    func testLostKeystrokesFailAfterFiveSecondsWithoutProgress() {
        let reads: [Read] = stride(from: 0.3, through: 12, by: 0.3).map { ($0, "R", $0 + 0.05) }
        let (result, progress) = verdict("Reminders", reads)
        XCTAssertEqual(result, .noProgress)
        XCTAssertEqual(progress.lastSeen, "R")
        let failedAt = progress.lastSeenAt ?? .infinity
        XCTAssertGreaterThanOrEqual(failedAt, 0.35 + TypingProgress.noProgressLimit)
        XCTAssertLessThan(failedAt, 0.35 + TypingProgress.noProgressLimit + 0.5)
        XCTAssertTrue(progress.describe(result).contains("\"R\""))
    }

    /// "Show t" then nothing: also no progress, never sent as a fragment.
    func testStalledFragmentFails() {
        let reads: [Read] = [(1, "Show t", 1.05)] + stride(from: 1.3, through: 8, by: 0.3).map { ($0, "Show t", $0 + 0.05) }
        XCTAssertEqual(verdict("Show this week", reads).0, .noProgress)
    }

    func testGarbledTextFailsOnTheFirstRead() {
        let reads: [Read] = [(1, "Shxw", 1.05), (1.3, "Show this week", 1.35)]
        let (result, progress) = verdict("Show this week", reads)
        XCTAssertEqual(result, .notAPrefix)
        XCTAssertEqual(progress.lastSeen, "Shxw")
    }

    /// One new character every 4 s keeps resetting the allowance, but the
    /// 20 s cap still ends the wait.
    func testSlowSteadyTypingStopsAtTheTwentySecondCap() {
        let text = "Show this week"
        let reads: [Read] = (1...8).map { step in
            let t = Double(step) * 4 - 3.5
            return (t, String(text.prefix(step)), t + 0.05)
        }
        XCTAssertEqual(verdict(text, reads).0, .overCap)
    }

    /// A failed read is no progress, and the message says nothing was readable.
    func testUnreadableFieldFailsWithoutProgress() {
        let reads: [Read] = stride(from: 0.3, through: 8, by: 0.3).map { ($0, nil, $0 + 0.05) }
        let (result, progress) = verdict("History", reads)
        XCTAssertEqual(result, .noProgress)
        XCTAssertTrue(progress.describe(result).contains("nothing readable"))
    }
}
