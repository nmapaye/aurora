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

    /// Generic oral first-order uptake rate constant (h⁻¹). Gives a typical
    /// ~35–42 minute peak across 3–8 h half-lives and converges smoothly onto
    /// exponential half-life decay after ~2 hours without inventing per-drink rates.
    public static let absorptionRatePerHour: Double = 5.5

    /// Time to peak concentration in minutes under `absorptionRatePerHour`
    /// for a given elimination half-life.
    public static func peakAbsorptionMinutes(halfLifeHours: Double) -> Double {
        guard halfLifeHours.isFinite, halfLifeHours > 0 else { return 0 }
        let ke = log(2.0) / halfLifeHours
        return (log(1.0 + absorptionRatePerHour / ke) / absorptionRatePerHour) * 60.0
    }

    /// Modeled active caffeine from one dose after `elapsedMs`, optionally
    /// applying the generic oral absorption onset ramp (`1 − e^(−ka · t)`).
    public static func singleDoseMg(
        mg: Double,
        elapsedMs: Millis,
        halfLifeHours: Double,
        useAbsorptionRamp: Bool = false
    ) -> Double {
        guard mg.isFinite, mg > 0,
              elapsedMs.isFinite, elapsedMs >= 0,
              halfLifeHours.isFinite, halfLifeHours > 0 else { return 0 }
        let halfLifeMs = halfLifeHours * hourMs
        let decay = pow(0.5, elapsedMs / halfLifeMs)
        guard useAbsorptionRamp else { return mg * decay }
        let elapsedHours = elapsedMs / hourMs
        let uptake = 1.0 - exp(-absorptionRatePerHour * elapsedHours)
        return mg * uptake * decay
    }

    /// Active caffeine at `now` with optional gradual oral onset ramp.
    public static func activeMg(
        at now: Millis,
        doses: [Dose],
        halfLifeHours: Double,
        useAbsorptionRamp: Bool
    ) -> Double {
        guard useAbsorptionRamp else {
            return activeMg(at: now, doses: doses, halfLifeHours: halfLifeHours)
        }
        return doses.reduce(0) { total, dose in
            guard dose.timestamp <= now else { return total }
            return total + singleDoseMg(
                mg: dose.mg,
                elapsedMs: now - dose.timestamp,
                halfLifeHours: halfLifeHours,
                useAbsorptionRamp: true
            )
        }
    }

    /// `1 − e^(−mg/100)`, between 0 and 1, with optional gradual onset ramp.
    public static func activeEffect(
        at now: Millis,
        doses: [Dose],
        halfLifeHours: Double,
        useAbsorptionRamp: Bool
    ) -> Double {
        let mg = activeMg(at: now, doses: doses, halfLifeHours: halfLifeHours, useAbsorptionRamp: useAbsorptionRamp)
        return 1 - exp(-mg / 100)
    }
}

public enum Circadian {
    public static let defaultTroughHour: Double = 3.0
    public static let anchorWindowDays: Int = 14
    public static let earlyReadNights: Int = 5
    public static let fullPersonalNights: Int = 7

    public struct Anchor: Codable, Equatable, Sendable {
        public enum Source: String, Codable, Equatable, Sendable {
            case defaultFixed
            case earlyRead
            case personalized
        }

        public var source: Source
        public var troughHour: Double
        public var recordedNights: Int
        public var includesSample: Bool

        public static let defaultFixed = Anchor(
            source: .defaultFixed,
            troughHour: defaultTroughHour,
            recordedNights: 0,
            includesSample: false
        )

        public init(source: Source, troughHour: Double, recordedNights: Int, includesSample: Bool) {
            self.source = source
            self.troughHour = troughHour
            self.recordedNights = recordedNights
            self.includesSample = includesSample
        }

        /// Formats a fractional 24-hour clock value in `[0, 24)` as e.g. `"3:45 AM"`.
        public static func formatClockHour(_ hour: Double) -> String {
            guard hour.isFinite else { return "3:00 AM" }
            let wrapped = ((hour.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
            let totalMinutes = ((jsRoundInt(wrapped * 60) % (24 * 60)) + 24 * 60) % (24 * 60)
            let h24 = totalMinutes / 60
            let m = totalMinutes % 60
            let period = h24 < 12 ? "AM" : "PM"
            let h12 = h24 % 12 == 0 ? 12 : h24 % 12
            return String(format: "%d:%02d %@", h12, m, period)
        }
    }

    /// Time-of-day term from the whole local hour, lowest at 3 AM and highest
    /// at 3 PM.
    public static func value(at now: Millis, clock: LocalClock) -> Double {
        let hour = Double(clock.hour(now))
        return 0.5 - 0.5 * cos(2 * Double.pi * ((hour - 3) / 24))
    }

    private static func fractionalHour(_ ms: Millis, clock: LocalClock) -> Double {
        let comps = clock.calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: ms / 1000))
        return Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
    }

    /// Time-of-day term anchored to `troughHour` using continuous local hour+minute.
    public static func value(at now: Millis, clock: LocalClock, troughHour: Double) -> Double {
        let hour = fractionalHour(now, clock: clock)
        return 0.5 - 0.5 * cos(2 * Double.pi * ((hour - troughHour) / 24))
    }

    /// Circular median sleep-midpoint phase anchor over the preceding 14 days
    /// of recorded main sleeps (3–16 h after merging brief awakenings).
    public static func anchor(sleeps: [SleepSession], at now: Millis, clock: LocalClock) -> Anchor {
        let windowStart = now - Double(anchorWindowDays) * dayMs
        let valid = sleeps.filter {
            $0.start.isFinite && $0.end.isFinite && $0.end > $0.start && $0.end <= now && $0.end > windowStart
        }
        let mainBlocks = SleepIntervals.merge(valid, gapMs: SleepIntervals.briefAwakeningMs).filter {
            let duration = $0.end - $0.start
            return duration >= 3 * hourMs && duration <= 16 * hourMs
        }
        var byDay: [String: Interval] = [:]
        for interval in mainBlocks {
            let key = clock.dayKey(interval.end)
            if let existing = byDay[key] {
                let existingDuration = existing.end - existing.start
                let duration = interval.end - interval.start
                if duration > existingDuration || (duration == existingDuration && interval.start < existing.start) {
                    byDay[key] = interval
                }
            } else {
                byDay[key] = interval
            }
        }
        let nightCount = byDay.count
        guard nightCount >= earlyReadNights else {
            return Anchor(source: .defaultFixed, troughHour: defaultTroughHour, recordedNights: nightCount, includesSample: false)
        }

        let selected = Array(byDay.values)
        let includesSample = valid.contains { session in
            RecordID.isSample(session.id) && selected.contains { session.end > $0.start && session.start < $0.end }
        }

        var sumSin = 0.0
        var sumCos = 0.0
        var angles: [Double] = []
        angles.reserveCapacity(selected.count)
        for interval in selected {
            let mid = (interval.start + interval.end) / 2.0
            let h = fractionalHour(mid, clock: clock)
            let theta = h * 2.0 * Double.pi / 24.0
            angles.append(theta)
            sumSin += sin(theta)
            sumCos += cos(theta)
        }

        let meanAngle = atan2(sumSin, sumCos)
        let deltas = angles.map { atan2(sin($0 - meanAngle), cos($0 - meanAngle)) }.sorted()
        let midIdx = deltas.count / 2
        let medianDelta = deltas.count.isMultiple(of: 2)
            ? (deltas[midIdx - 1] + deltas[midIdx]) / 2.0
            : deltas[midIdx]

        let rawHours = (meanAngle + medianDelta) * 24.0 / (2.0 * Double.pi)
        let normalized = ((rawHours.truncatingRemainder(dividingBy: 24.0)) + 24.0).truncatingRemainder(dividingBy: 24.0)
        var rounded = jsRound(normalized * 12.0) / 12.0
        if rounded >= 24.0 { rounded -= 24.0 }
        if rounded < 0 { rounded += 24.0 }

        return Anchor(
            source: nightCount >= fullPersonalNights ? .personalized : .earlyRead,
            troughHour: rounded,
            recordedNights: nightCount,
            includesSample: includesSample
        )
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
    // The model's weights, named once so contribution breakdowns use the
    // same numbers as the score.
    public static let baseline: Double = 30
    public static let circadianWeight: Double = 50
    public static let caffeineWeight: Double = 40
    public static let sleepDebtWeight: Double = 40
    public static let inertiaWeight: Double = 100

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
        return clamp(
            baseline + circadianWeight * circadian + caffeineWeight * effect - sleepDebtWeight * debt - inertiaWeight * inertia,
            0, 100
        )
    }

    /// Variant supporting optional personalized circadian trough hour and
    /// gradual caffeine onset ramp.
    public static func score(
        at now: Millis,
        doses: [Dose],
        sleeps: [SleepSession],
        halfLifeHours: Double,
        targetSleepHours: Double,
        clock: LocalClock,
        circadianTroughHour: Double?,
        useAbsorptionRamp: Bool = false
    ) -> Double {
        let effect = Caffeine.activeEffect(
            at: now,
            doses: doses,
            halfLifeHours: halfLifeHours,
            useAbsorptionRamp: useAbsorptionRamp
        )
        let circadian = circadianTroughHour.map {
            Circadian.value(at: now, clock: clock, troughHour: $0)
        } ?? Circadian.value(at: now, clock: clock)
        let debt = SleepDebt.value(at: now, sleeps: sleeps, targetHours: targetSleepHours)
        let inertia = SleepInertia.value(at: now, sleeps: sleeps)
        return clamp(
            baseline + circadianWeight * circadian + caffeineWeight * effect - sleepDebtWeight * debt - inertiaWeight * inertia,
            0, 100
        )
    }
}
