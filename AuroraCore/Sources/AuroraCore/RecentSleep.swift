import Foundation

/// One wake day in the recent-sleep summary. `asleepMs` is nil when no main
/// sleep is recorded for that day: a missing night is never 0, and a nap or
/// a short sample on its own isn't a night.
public struct RecentSleepNight: Equatable, Sendable {
    public var dayKey: String
    /// Local midnight of the wake day.
    public var dayStart: Millis
    /// Every episode that woke on this day, naps and short sleep included.
    public var asleepMs: Millis?
}

/// Why `RecentSleepSummary.shortfallMs` is missing.
public enum ShortfallReason: Equatable, Sendable {
    /// No sleep target is set. No reference is substituted.
    case noTarget
    case tooFewNights(recorded: Int, required: Int)
}

/// Recent sleep for the screens and, later, the energy model
/// (docs/research/sleep-and-check-in.md §4 R3, §6). Pure: it reads only the
/// sessions given and `now`.
public struct RecentSleepSummary: Equatable, Sendable {
    /// Union of asleep time overlapping the 24 and 48 hours before `now`.
    public var asleepLast24hMs: Millis
    public var asleepLast48hMs: Millis
    /// The most recent main sleep ending at or before `now`.
    public var lastMain: SleepEpisodeV2?
    /// Seven wake days, oldest first. They end today once today has a main
    /// sleep, otherwise yesterday, so a night still to come isn't missing.
    public var nights: [RecentSleepNight]
    public var recordedNights: Int
    /// Mean over recorded nights only; nil with none.
    public var meanAsleepMs: Millis?
    /// `max(0, Σ(target − day total))` over recorded nights. Needs a target
    /// and `RecentSleep.minimumRecordedNights`; otherwise nil with the reason.
    public var shortfallMs: Millis?
    public var shortfallUnavailable: ShortfallReason?
    /// From `lastMain.end` to `now`.
    public var msSinceMainWake: Millis?
}

public enum RecentSleep {
    /// Recorded nights of seven needed before a shortfall is shown. Aili 2017.
    public static let minimumRecordedNights = 5
    public static let windowDays = 7

    /// Union of asleep time inside `[from, to]`, overlaps counted once.
    public static func asleepMs(_ sessions: [SleepSession], from: Millis, to: Millis) -> Millis {
        SleepIntervals.merge(sessions).reduce(0) { total, interval in
            let start = max(interval.start, from)
            let end = min(interval.end, to)
            return end > start ? total + (end - start) : total
        }
    }

    public static func summarize(_ sessions: [SleepSession], targetHours: Double?, now: Millis, clock: LocalClock) -> RecentSleepSummary {
        let episodes = SleepEpisodes.build(sessions, now: now, clock: clock)
        let mains = episodes.filter { $0.kind == .main }
        let mainDays = Set(mains.map(\.wakeDayKey))
        let totals = SleepEpisodes.asleepByWakeDay(episodes)
        let lastDay = mainDays.contains(clock.dayKey(now)) ? now : clock.addingDays(-1, to: now)
        let nights = clock.dayStarts(endingAt: lastDay, days: windowDays).map { start -> RecentSleepNight in
            let key = clock.dayKey(start)
            return RecentSleepNight(dayKey: key, dayStart: start, asleepMs: mainDays.contains(key) ? totals[key] : nil)
        }
        let recorded = nights.compactMap(\.asleepMs)
        let lastMain = mains.max { $0.end < $1.end }

        var shortfall: Millis?
        var unavailable: ShortfallReason?
        if let targetHours, targetHours > 0 {
            if recorded.count >= minimumRecordedNights {
                shortfall = max(0, recorded.reduce(0) { $0 + (targetHours * hourMs - $1) })
            } else {
                unavailable = .tooFewNights(recorded: recorded.count, required: minimumRecordedNights)
            }
        } else {
            unavailable = .noTarget
        }

        return RecentSleepSummary(
            asleepLast24hMs: asleepMs(sessions, from: now - 24 * hourMs, to: now),
            asleepLast48hMs: asleepMs(sessions, from: now - 48 * hourMs, to: now),
            lastMain: lastMain,
            nights: nights,
            recordedNights: recorded.count,
            meanAsleepMs: recorded.isEmpty ? nil : recorded.reduce(0, +) / Double(recorded.count),
            shortfallMs: shortfall,
            shortfallUnavailable: unavailable,
            msSinceMainWake: lastMain.map { now - $0.end }
        )
    }

    /// "Recorded sleep, last 7 days: 6 of 7 nights, average 6 h 45 min",
    /// then the shortfall against the person's own target when there is one.
    /// Nothing is said about a target that isn't set.
    public static func describe(_ summary: RecentSleepSummary, targetHours: Double?) -> String {
        guard let mean = summary.meanAsleepMs else { return "Recorded sleep, last 7 days: No record." }
        var text = "Recorded sleep, last 7 days: \(summary.recordedNights) of \(windowDays) nights, average \(formatHoursMinutes(durationMs: mean))"
        if let shortfall = summary.shortfallMs, let targetHours {
            let target = formatGap(durationMs: targetHours * hourMs)
            text += shortfall < minuteMs
                ? " · At or over your \(target) target across recorded nights"
                : " · \(formatHoursMinutes(durationMs: shortfall)) under your \(target) target across recorded nights"
        }
        return text + "."
    }
}
