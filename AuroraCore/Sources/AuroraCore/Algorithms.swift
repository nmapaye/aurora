import Foundation

// The estimate models from the React Native build, unchanged. Each one reads
// only the records it is given and the instant `now`.

public enum Caffeine {
    /// Active caffeine at `now`: every dose at or before `now`, halved once
    /// per half-life.
    public static func activeMg(at now: Millis, doses: [Dose], halfLifeHours: Double) -> Double {
        let halfLifeMs = halfLifeHours * hourMs
        return doses.reduce(0) { total, dose in
            guard dose.timestamp <= now else { return total }
            let elapsed = now - dose.timestamp
            return total + dose.mg * pow(0.5, elapsed / halfLifeMs)
        }
    }

    /// `1 − e^(−mg/100)`, between 0 and 1.
    public static func activeEffect(at now: Millis, doses: [Dose], halfLifeHours: Double) -> Double {
        let mg = activeMg(at: now, doses: doses, halfLifeHours: halfLifeHours)
        return 1 - exp(-mg / 100)
    }
}

public enum Circadian {
    /// Time-of-day term from the whole local hour, lowest at 3 AM and highest
    /// at 3 PM.
    public static func value(at now: Millis, clock: LocalClock) -> Double {
        let hour = Double(clock.hour(now))
        return 0.5 - 0.5 * cos(2 * Double.pi * ((hour - 3) / 24))
    }
}

public enum SleepIntervals {
    /// Awakenings shorter than this are treated as part of one sleep episode.
    public static let briefAwakeningMs: Millis = 30 * minuteMs

    /// Merges overlapping intervals, or ones within `gapMs` of each other, so
    /// stage segments and duplicate sources (Watch and iPhone) count once.
    public static func merge(_ intervals: [Interval], gapMs: Millis = 0) -> [Interval] {
        let ordered = intervals
            .filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }
        var merged: [Interval] = []
        for interval in ordered {
            if let last = merged.last, interval.start <= last.end + gapMs {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    public static func merge(_ sleeps: [SleepSession], gapMs: Millis = 0) -> [Interval] {
        merge(sleeps.map { Interval(start: $0.start, end: $0.end) }, gapMs: gapMs)
    }
}

public enum SleepDebt {
    public static func totalHoursLast24(at now: Millis, sleeps: [SleepSession]) -> Double {
        let from = now - 24 * hourMs
        return SleepIntervals.merge(sleeps).reduce(0) { total, interval in
            let start = max(interval.start, from)
            let end = min(interval.end, now)
            return end > start ? total + (end - start) / hourMs : total
        }
    }

    /// The share of the target missing from the last 24 hours, from 0 to 1.
    public static func value(at now: Millis, sleeps: [SleepSession], targetHours: Double) -> Double {
        let hours = totalHoursLast24(at: now, sleeps: sleeps)
        return clamp((targetHours - hours) / targetHours, 0, 1)
    }
}

public enum SleepInertia {
    /// Minutes since the end of the latest sleep episode at or before `now`,
    /// or infinity when there is none.
    public static func minutesSinceLastWake(at now: Millis, sleeps: [SleepSession]) -> Double {
        let started = sleeps.filter { $0.start <= now }
        let latestEnd = SleepIntervals.merge(started, gapMs: SleepIntervals.briefAwakeningMs)
            .filter { $0.end <= now }
            .map(\.end)
            .max()
        guard let latestEnd else { return .infinity }
        return (now - latestEnd) / minuteMs
    }

    public static func value(at now: Millis, sleeps: [SleepSession]) -> Double {
        let minutes = minutesSinceLastWake(at: now, sleeps: sleeps)
        return minutes <= 90 ? 0.15 * exp(-minutes / 45) : 0
    }
}

public enum Alertness {
    /// `clamp(30 + 50C + 40E − 40S − 100I, 0, 100)`, unrounded.
    public static func score(
        at now: Millis,
        doses: [Dose],
        sleeps: [SleepSession],
        halfLifeHours: Double,
        targetSleepHours: Double,
        clock: LocalClock
    ) -> Double {
        let effect = Caffeine.activeEffect(at: now, doses: doses, halfLifeHours: halfLifeHours)
        let circadian = Circadian.value(at: now, clock: clock)
        let debt = SleepDebt.value(at: now, sleeps: sleeps, targetHours: targetSleepHours)
        let inertia = SleepInertia.value(at: now, sleeps: sleeps)
        return clamp(30 + 50 * circadian + 40 * effect - 40 * debt - 100 * inertia, 0, 100)
    }
}
