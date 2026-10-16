import Foundation

/// A span of minutes of the local day that may wrap past midnight:
/// `lower` 23:10 and `upper` 00:50 covers 1 h 40 min across midnight.
public struct MinuteOfDayRange: Equatable, Sendable {
    public var lower: Int
    public var upper: Int
}

/// The person's usual timing from their own main sleeps, in minutes after
/// local midnight (0–1439). Describes what was recorded; never a schedule.
public struct UsualTiming: Equatable, Sendable {
    public var midpointMinute: Int
    public var startMinute: Int
    public var wakeMinute: Int
    /// Main sleeps in the last 14 days that the medians use.
    public var nights: Int
    /// Middle 80% of midpoints, only with enough main sleeps in 30 days.
    public var middle80Midpoint: MinuteOfDayRange?
}

/// docs/research/sleep-and-check-in.md §4 R4. Circular medians, so a usual
/// midpoint just before or after midnight, or a daytime sleeper's, comes
/// out where it is rather than half a day away.
public enum UsualSleepTiming {
    public static let windowDays = 14
    /// Main sleeps in `windowDays` before anything is shown. Fischer 2021; Aili 2017.
    public static let minimumNights = 7
    public static let spreadWindowDays = 30
    /// Main sleeps in `spreadWindowDays` before a spread is shown, matching
    /// the caffeine-timing gate.
    public static let spreadMinimumNights = 14
    /// Longer spans are implausible as one sleep and are left out.
    public static let maximumSpanMs: Millis = 16 * hourMs
    static let minutesPerDay = 1440

    public static func compute(_ episodes: [SleepEpisodeV2], now: Millis, clock: LocalClock) -> UsualTiming? {
        let mains = episodes.filter { $0.kind == .main && $0.end <= now && $0.spanMs <= maximumSpanMs }
        let recent = mains.filter { $0.end > now - Millis(windowDays) * dayMs }
        guard recent.count >= minimumNights else { return nil }
        let monthly = mains.filter { $0.end > now - Millis(spreadWindowDays) * dayMs }
        return UsualTiming(
            midpointMinute: circularMedian(recent.map { minuteOfDay(midpoint($0), clock: clock) }),
            startMinute: circularMedian(recent.map { minuteOfDay($0.start, clock: clock) }),
            wakeMinute: circularMedian(recent.map { minuteOfDay($0.end, clock: clock) }),
            nights: recent.count,
            middle80Midpoint: monthly.count >= spreadMinimumNights
                ? circularPercentileRange(monthly.map { minuteOfDay(midpoint($0), clock: clock) }, 0.1, 0.9)
                : nil
        )
    }

    public static func compute(_ sessions: [SleepSession], now: Millis, clock: LocalClock) -> UsualTiming? {
        compute(SleepEpisodes.build(sessions, now: now, clock: clock), now: now, clock: clock)
    }

    static func midpoint(_ episode: SleepEpisodeV2) -> Millis {
        episode.start + (episode.end - episode.start) / 2
    }

    static func minuteOfDay(_ ms: Millis, clock: LocalClock) -> Int {
        let parts = clock.calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: ms / 1000))
        return ((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) % minutesPerDay
    }

    static func wrap(_ minute: Int) -> Int {
        ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay
    }

    /// Rotation that puts the circular mean at 12:00, so the values sit
    /// together away from the midnight seam.
    static func rotation(_ minutes: [Int]) -> Int {
        var sinSum = 0.0, cosSum = 0.0
        for minute in minutes {
            let angle = Double(minute) / Double(minutesPerDay) * 2 * Double.pi
            sinSum += sin(angle)
            cosSum += cos(angle)
        }
        var mean = atan2(sinSum, cosSum) / (2 * Double.pi) * Double(minutesPerDay)
        if mean < 0 { mean += Double(minutesPerDay) }
        return 720 - Int(mean.rounded())
    }

    /// Rotate so the circular mean sits at 12:00, take the median (the mean
    /// of the middle two for an even count), then rotate back.
    static func circularMedian(_ minutes: [Int]) -> Int {
        guard !minutes.isEmpty else { return 0 }
        let shift = rotation(minutes)
        let rotated = minutes.map { wrap($0 + shift) }.sorted()
        let middle = rotated.count / 2
        let median = rotated.count.isMultiple(of: 2)
            ? Int((Double(rotated[middle - 1] + rotated[middle]) / 2).rounded())
            : rotated[middle]
        return wrap(median - shift)
    }

    static func circularPercentileRange(_ minutes: [Int], _ low: Double, _ high: Double) -> MinuteOfDayRange? {
        guard !minutes.isEmpty else { return nil }
        let shift = rotation(minutes)
        let rotated = minutes.map { wrap($0 + shift) }.sorted()
        func at(_ q: Double) -> Int {
            rotated[Int(clamp(jsRound(q * Double(rotated.count - 1)), 0, Double(rotated.count - 1)))]
        }
        return MinuteOfDayRange(lower: wrap(at(low) - shift), upper: wrap(at(high) - shift))
    }

    /// "Usual midpoint 3:00 AM · wake 7:00 AM · 8 nights".
    public static func describe(_ timing: UsualTiming, formatMinute: (Int) -> String) -> String {
        "Usual midpoint \(formatMinute(timing.midpointMinute)) · wake \(formatMinute(timing.wakeMinute)) · \(timing.nights) nights"
    }

    /// Progress below the gate, never a number.
    public static func gatheringText(nights: Int) -> String {
        "\(nights) of \(minimumNights) main sleeps in the last \(windowDays) days. Usual timing appears at \(minimumNights)."
    }
}
