import Foundation

/// Health sleep samples arrive as start/end pairs. Only the asleep values are
/// kept; in-bed and awake samples are not sleep.
public struct HealthSleepSample: Equatable, Sendable {
    public var start: Millis
    public var end: Millis

    public init(start: Millis, end: Millis) {
        self.start = start
        self.end = end
    }
}

public enum HealthImport {
    public static let refreshDays: Double = 30
    public static let onboardingImportDays: Double = 14
    /// Foreground refreshes run at most this often.
    public static let refreshIntervalMs: Millis = 15 * minuteMs

    public static let noSleepMessage =
        "No recent sleep found in Health. Check that Aurora can read Sleep in the Health app, or add sleep manually."
    public static let importingMessage = "Importing recent sleep from Health."

    /// HealthKit `HKCategoryValueSleepAnalysis` raw values that mean asleep:
    /// asleep (unspecified) 1, core 3, deep 4, REM 5.
    public static let asleepValues: Set<Int> = [1, 3, 4, 5]

    /// Nights rather than samples: one Watch night can be dozens of stage
    /// segments.
    public static func countNights(_ samples: [HealthSleepSample]) -> Int {
        SleepIntervals.merge(samples.map { Interval(start: $0.start, end: $0.end) }, gapMs: SleepIntervals.briefAwakeningMs).count
    }

    public static func describeImportedNights(_ nights: Int) -> String {
        nights > 0 ? "Imported \(nights) \(nights == 1 ? "night" : "nights") of sleep from Health." : noSleepMessage
    }

    public static func sessions(from samples: [HealthSleepSample]) -> [SleepSession] {
        samples.map { SleepSession(id: HealthSleepIdentity.id(start: $0.start, end: $0.end), start: $0.start, end: $0.end, type: .sleep) }
    }

    /// Applies an import of the last `days` to `state`, replacing Aurora's
    /// copy of that window so edits and deletions made in Health carry over.
    public static func apply(
        _ samples: [HealthSleepSample],
        days: Double,
        now: Millis,
        to state: inout AppState
    ) -> Int {
        let windowStart = now - days * dayMs
        state.replaceHealthSleepWindow(sessions(from: samples), windowStart: windowStart, windowEnd: now, now: now)
        let nights = countNights(samples)
        state.healthSync.importedCount = nights
        state.healthSync.importStatus = .succeeded
        state.healthSync.lastSyncedAt = now
        state.healthSync.lastMessage = describeImportedNights(nights)
        return nights
    }

    public static func recordFailure(_ message: String, prefix: String = "Health refresh failed.", now: Millis, to state: inout AppState) {
        state.healthSync.importStatus = .failed
        state.healthSync.lastSyncedAt = now
        state.healthSync.lastMessage = "\(prefix) \(message)"
    }

    /// Whether a quiet foreground Health refresh is due.
    public static func shouldRefresh(state: AppState, now: Millis) -> Bool {
        guard state.onboarding.completed, !state.demoMode,
              state.onboarding.permissionStatus == .granted,
              state.healthSync.importStatus != .importing else { return false }
        guard let last = state.healthSync.lastSyncedAt else { return true }
        return now - last >= refreshIntervalMs
    }
}
