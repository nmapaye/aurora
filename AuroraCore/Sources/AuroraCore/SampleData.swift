import Foundation

/// Bundled Sample Data. Every record's id starts with `demo:`, which is what
/// labels it as sample and keeps it read-only.
public struct SampleSnapshot: Equatable, Sendable {
    public var doses: [Dose]
    public var sleeps: [SleepSession]
    public var vigilanceSessions: [VigilanceSession]
}

public enum SampleData {
    // Offsets are whole 24-hour days back from local midnight, as in the
    // original, not calendar days.
    private static let dosePattern: [(day: Double, hour: Double, mg: Double, source: String)] = [
        (13, 8.25, 95, "Demo drip"),
        (13, 13.5, 60, "Demo matcha"),
        (12, 9, 95, "Demo drip"),
        (11, 8.5, 70, "Demo tea"),
        (10, 14, 80, "Demo cold brew"),
        (9, 9.25, 95, "Demo drip"),
        (8, 12.75, 60, "Demo matcha"),
        (7, 8.75, 95, "Demo drip"),
        (6, 15.25, 40, "Demo tea"),
        (5, 9, 120, "Demo espresso"),
        (4, 13.25, 60, "Demo matcha"),
        (3, 8.5, 95, "Demo drip"),
        (2, 14.5, 80, "Demo cold brew"),
        (1, 9.25, 95, "Demo drip"),
        (0, 8.5, 95, "Demo drip"),
        (0, 12.25, 60, "Demo matcha"),
    ]

    public static func snapshot(now: Millis, clock: LocalClock) -> SampleSnapshot {
        let today = clock.startOfDay(now)
        let doses = dosePattern.enumerated().map { index, item in
            Dose(
                id: "demo:dose:\(index)",
                timestamp: today - item.day * dayMs + item.hour * hourMs,
                mg: item.mg,
                source: item.source,
                note: "Sample data"
            )
        }
        let sleeps = (0..<10).map { index -> SleepSession in
            let dayStart = today - Double(index) * dayMs
            return SleepSession(
                id: "demo:sleep:\(index)",
                start: dayStart - 1.25 * hourMs,
                end: dayStart + (6.75 + Double(index % 3) * 0.25) * hourMs,
                type: .sleep
            )
        }
        // Current-version tests: ten cues each, built and scored the way a
        // real run is, so they plot and compare with the person's own tests.
        let reactions: [[Double?]] = [
            [248, 262, 271, 239, 285, 256, 266, 252, 291, 244],
            [266, 281, 412, 259, 290, 274, 301, 268, 285, 277],
            [281, 305, nil, 298, 322, 276, 311, 445, 293, 288],
        ]
        let tests = reactions.enumerated().map { index, times -> VigilanceSession in
            let completedAt = today - Double(index) * 2 * dayMs + 15 * hourMs
            let startedAt = completedAt - Vigilance.testDurationMs
            let trials = times.enumerated().map { trial, reaction in
                VigilanceTrial(cueAt: startedAt + 1_500 + Double(trial) * 2_800, reactionMs: reaction, cueLatencyMs: 8)
            }
            let falseStarts = index == 2 ? [VigilanceFalseStart(at: startedAt + 9_000)] : []
            return Vigilance.buildSession(
                id: "demo:vigilance:\(index)", startedAt: startedAt, completedAt: completedAt,
                trials: trials, falseStarts: falseStarts, deviceModel: nil
            )
        }
        return SampleSnapshot(doses: doses, sleeps: sleeps, vigilanceSessions: tests)
    }
}
