import Foundation

/// First-run setup copy. Never reports Health access as granted: HealthKit
/// does not reveal read decisions.
public enum OnboardingCopy {
    public static let stepCount = 3
    public static let sleepTargetRange: ClosedRange<Double> = 5...10
    public static let sleepTargetStep: Double = 0.5
    public static let sleepTargetPresets: [Double] = [7, 8, 9]
    /// Two columns need this much width, and text no larger than this scale.
    public static let splitLayoutMinWidth: Double = 800
    public static let splitLayoutMaxFontScale: Double = 1.35

    public enum LayoutMode: Sendable {
        case stacked
        case split
    }

    public static func layoutMode(width: Double, fontScale: Double) -> LayoutMode {
        width >= splitLayoutMinWidth && fontScale <= splitLayoutMaxFontScale ? .split : .stacked
    }

    public struct StepCopy: Equatable, Sendable {
        public var eyebrow: String
        public var title: String
        public var body: String
        public var summaryLabel: String
    }

    public static func stepCopy(step: Int, source: OnboardingSource) -> StepCopy {
        switch step {
        case 0:
            return StepCopy(
                eyebrow: "Your nights",
                title: "How much sleep do you aim for?",
                body: "Aurora compares your sleep with this nightly target. You can change it anytime in Settings.",
                summaryLabel: "Sleep target"
            )
        case 1:
            return StepCopy(
                eyebrow: "Your sleep record",
                title: "Where should sleep come from?",
                body: "Read recent nights from Apple Health, or log them yourself.",
                summaryLabel: "Sleep source"
            )
        default:
            return source == .manual
                ? StepCopy(
                    eyebrow: "Access",
                    title: "Ready for manual logging",
                    body: "Aurora will not ask for Health access. You can connect Health later from Sleep.",
                    summaryLabel: "Health access"
                )
                : StepCopy(
                    eyebrow: "Access",
                    title: "Read-only access to Health",
                    body: "Aurora asks to read sleep only. You choose what to share in the Health sheet.",
                    summaryLabel: "Health access"
                )
        }
    }

    public static func formatSleepTarget(_ hours: Double) -> (value: String, unit: String, spoken: String) {
        // A stored target can be any finite number; saturate rather than trap.
        let value = hours.rounded() == hours ? String(saturatingInt(hours)) : String(format: "%.1f", hours)
        return (value, "hours", "\(value) hours")
    }

    public static func describeSleepSource(_ source: OnboardingSource) -> String {
        source == .manual ? "Manual logging" : "Apple Health"
    }

    public static func describeHealthAccess(source: OnboardingSource, permission: HealthPermissionStatus) -> String {
        if source == .manual { return "Not used" }
        switch permission {
        case .granted: return "Requested, read-only"
        case .denied: return "Request incomplete"
        case .unsupported: return "Unavailable"
        case .idle: return "Not requested yet"
        }
    }

    public enum StepState: Sendable {
        case done
        case current
        case upcoming
    }

    public static func stepState(index: Int, step: Int) -> StepState {
        if index < step { return .done }
        return index == step ? .current : .upcoming
    }

    public static func nextAction(
        source: OnboardingSource,
        permission: HealthPermissionStatus,
        importStatus: HealthImportStatus,
        importedCount: Int
    ) -> String {
        if source == .manual { return "Finish setup to log caffeine and sleep manually." }
        if permission != .granted { return "Connect Health, or finish with manual setup." }
        switch importStatus {
        case .succeeded:
            return importedCount > 0
                ? "Finish setup, then review imported sleep."
                : "Finish setup to log sleep manually, or check sleep records and access in Health."
        case .importing:
            return "Health access requested. Importing your sleep…"
        case .failed:
            return "Health access requested. The sleep import needs a retry."
        case .idle:
            return "Health access requested. Recent sleep hasn’t been imported yet."
        }
    }
}

public enum CutoffReminder {
    public static let identifier = "cutoff-reminder"

    public struct Content: Equatable, Sendable {
        public var title: String
        public var body: String
        public var hour: Int
        public var minute: Int
    }

    public static func content(cutoffHour: Double, clock: LocalClock, text: DateText) -> Content {
        let hour = Int(clamp(jsRound(cutoffHour), 0, 23))
        return Content(
            title: "Last call for caffeine",
            body: "After \(text.clockHour(Double(hour), clock: clock)), caffeine is likely to affect tonight's sleep.",
            hour: hour,
            minute: 0
        )
    }
}

/// Aurora describes what was recorded and estimates alertness. It never
/// prescribes doses, bedtimes, wake times, sleep-cycle schedules or a
/// universal caffeine limit. Tests run every user-facing string through this.
public enum CopyRules {
    public static let forbiddenPattern =
        #"\b(kickstart|top-up|suggested (bedtime|wake)|recommended (dose|bedtime|wake)|90-minute|sleep cycles?|safe (amount|dose|limit)|allowance|mg (left|remaining)|remaining (mg|caffeine)|you should (drink|sleep|stop)|limit adherence)\b"#

    /// Disclaimers that negate the idea are allowed.
    public static let allowedSentences = ["It is not a recommended or safe amount."]

    public static func violations(in text: String) -> [String] {
        var scrubbed = text
        for sentence in allowedSentences {
            scrubbed = scrubbed.replacingOccurrences(of: sentence, with: "")
        }
        guard let regex = try? NSRegularExpression(pattern: forbiddenPattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(scrubbed.startIndex..., in: scrubbed)
        return regex.matches(in: scrubbed, range: range).compactMap { match in
            Range(match.range, in: scrubbed).map { String(scrubbed[$0]) }
        }
    }
}
