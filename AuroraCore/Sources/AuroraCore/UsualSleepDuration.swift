import Foundation

/// The person's own usual asleep time, used as the model's reference when
/// no sleep target is set. Never stored as a target, never offered as one
/// in Setup or Settings, and always labelled where it is used.
///
/// Constant trace (in the style of docs/research/sleep-and-check-in.md §5):
///
/// | Constant | Value | Why | Source | Confidence |
/// |---|---|---|---|---|
/// | Statistic | Median asleep time of main sleeps | Robust to one very short or long night; the person's own history, compared only with itself | sleep-and-check-in §3 Q6, §4 R6 (own-history comparison) [I] | Medium |
/// | `windowDays` | 14 days | Matches the usual-timing window | §4 R4 (14 d) | Medium |
/// | `minimumNights` | 7 main sleeps | Matches the usual-timing gate; fewer nights give unstable estimates | Fischer 2021; Aili 2017 (§3 Q4) | Medium |
/// | Night being scored | Excluded | A short night must not lower its own reference | [I] | High |
/// | Kinds counted | Main sleeps only | Naps, short and secondary sleep aren't nights | §4 R2 episode rule | High |
///
/// A chosen target always wins. Below the gate the model's sleep-target term
/// is left out, labelled by `EnergyMissingInput.sleepTarget`.
public struct UsualSleepBaseline: Codable, Equatable, Sendable {
    /// Median asleep time of the counted main sleeps.
    public var asleepMs: Millis
    /// Main sleeps the median was taken over.
    public var nights: Int

    public var hours: Double { asleepMs / hourMs }

    /// "Compared with your usual 6h 50m (median of 9 nights). Not a recommendation."
    public var text: String {
        "Compared with your usual \(formatHoursMinutes(durationMs: asleepMs)) (median of \(nights) nights). Not a recommendation."
    }
}

/// What the model's sleep-target term compares recorded sleep with.
public enum SleepReference: Equatable, Sendable {
    case target(Double)
    case usual(UsualSleepBaseline)

    public var hours: Double {
        switch self {
        case .target(let hours): hours
        case .usual(let baseline): baseline.hours
        }
    }
}

public enum UsualSleepDuration {
    public static let windowDays = 14
    public static let minimumNights = 7

    /// Main sleeps that ended by `t` in the 14 days before it, without the
    /// latest one (the night being scored). Nil below `minimumNights`.
    public static func baseline(_ sessions: [SleepSession], at t: Millis, clock: LocalClock) -> UsualSleepBaseline? {
        let from = t - Millis(windowDays) * dayMs
        // Only what can join an episode ending in the window, so a long
        // history isn't regrouped at every modeled instant.
        let recent = sessions.filter { $0.end > from - dayMs && $0.end <= t }
        let mains = SleepEpisodes.build(recent, now: t, clock: clock)
            .filter { $0.kind == .main && $0.end > from }
            .sorted { $0.end < $1.end }
        let counted = mains.dropLast().map(\.asleepMs)
        guard counted.count >= minimumNights else { return nil }
        return UsualSleepBaseline(asleepMs: median(counted), nights: counted.count)
    }

    /// The middle value, or the mean of the middle two for an even count.
    static func median(_ values: [Millis]) -> Millis {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

extension EstimateInputs {
    /// The person's target when they chose one, else their usual sleep once
    /// there is enough of it, else nil (the term is left out).
    public func sleepReference(at t: Millis, sleeps: [SleepSession]) -> SleepReference? {
        if let targetSleepHours { return .target(targetSleepHours) }
        return UsualSleepDuration.baseline(sleeps, at: t, clock: clock).map(SleepReference.usual)
    }
}
