import Foundation

/// Estimated Alertness is the alertness model, nothing more. Without a single
/// sleep block of at least three hours reaching the 18 hours before `t`, the
/// number would describe missing data rather than the person, so there is no
/// score.
public enum AlertnessEstimate: Equatable, Sendable {
    case estimated(score: Int, sleepHours: Double, includesSample: Bool)
    case needsSleep

    public var score: Int? {
        if case .estimated(let score, _, _) = self { return score }
        return nil
    }
}

public struct EstimateInputs: Sendable {
    public var halfLifeHours: Double
    public var targetSleepHours: Double
    public var clock: LocalClock

    public init(halfLifeHours: Double, targetSleepHours: Double, clock: LocalClock) {
        self.halfLifeHours = halfLifeHours
        self.targetSleepHours = targetSleepHours
        self.clock = clock
    }

    /// A stored `prefs.tz` sets the zone for the time-of-day term, as it did
    /// in the original model; otherwise `clock`'s zone applies.
    public init(prefs: Prefs, clock: LocalClock) {
        let zone = prefs.tz.flatMap(TimeZone.init(identifier:))
        self.init(
            halfLifeHours: prefs.halfLife,
            targetSleepHours: prefs.targetSleep,
            clock: zone.map(LocalClock.init(timeZone:)) ?? clock
        )
    }
}

public enum Summary {
    public static func estimateAlertness(
        at t: Millis,
        doses: [Dose],
        sleeps: [SleepSession],
        inputs: EstimateInputs
    ) -> AlertnessEstimate {
        // Display eligibility constants carried from the missing-night fix;
        // these are Aurora assumptions, not validated clinical thresholds.
        // Count ongoing records only as far as the evaluation instant.
        let hasRecentMainSleep = SleepIntervals.merge(
            sleeps.filter { $0.start < t }.map { Interval(start: $0.start, end: min($0.end, t)) },
            gapMs: SleepIntervals.briefAwakeningMs
        ).contains {
            $0.end >= t - 18 * hourMs && $0.end - $0.start >= 3 * hourMs
        }
        guard hasRecentMainSleep else { return .needsSleep }
        let sleepHours = SleepDebt.totalHoursLast24(at: t, sleeps: sleeps)
        let windowStart = t - dayMs
        let includesSample =
            sleeps.contains { $0.end > windowStart && $0.start <= t && RecordID.isSample($0.id) } ||
            doses.contains { $0.timestamp > windowStart && $0.timestamp <= t && RecordID.isSample($0.id) }
        let score = Alertness.score(
            at: t,
            doses: doses,
            sleeps: sleeps,
            halfLifeHours: inputs.halfLifeHours,
            targetSleepHours: inputs.targetSleepHours,
            clock: inputs.clock
        )
        return .estimated(score: jsRoundInt(score), sleepHours: sleepHours, includesSample: includesSample)
    }

    /// `estimateNote` adds "This is an estimate, not a measurement." Keep it
    /// for spoken text with no visual label; text that already says
    /// "Estimated" and "Modeled" leaves it out (one honesty label per fact).
    public static func describe(_ estimate: AlertnessEstimate, estimateNote: Bool = true) -> String {
        switch estimate {
        case .needsSleep:
            return "Estimated alertness unavailable. No recorded sleep block of at least 3 hours reaches the last 18 hours."
        case .estimated(let score, let sleepHours, let includesSample):
            return "Estimated alertness \(score) out of 100. Modeled from \(formatSleepHours(sleepHours)) of sleep in the last 24 hours, active caffeine, and time of day.\(includesSample ? " Includes Sample Data." : "")\(estimateNote ? " This is an estimate, not a measurement." : "")"
        }
    }

    public struct CutoffAnnotation: Equatable, Sendable {
        /// Today's cutoff, which is where the curve marks it.
        public var at: Millis
        public var isPast: Bool
        /// The next cutoff to come: today's, or tomorrow's once today's has passed.
        public var nextAt: Millis
        public var text: String
    }

    /// The user's own cutoff as context on today's curve, not a
    /// recommendation. After the cutoff it only matters if caffeine was
    /// logged today. Tomorrow's cutoff comes from the calendar day, so DST
    /// keeps the same local hour.
    public static func cutoffAnnotation(
        now: Millis,
        cutoffHour: Double?,
        doses: [Dose],
        clock: LocalClock,
        formatTime: (Millis) -> String
    ) -> CutoffAnnotation? {
        // No marker until the person sets a cutoff time.
        guard let cutoffHour, cutoffHour.isFinite else { return nil }
        let hour = Int(clamp(jsRound(cutoffHour), 0, 23))
        let at = clock.setTime(now, hour: hour)
        let isPast = now >= at
        if isPast {
            let dayStart = clock.startOfDay(now)
            let loggedToday = doses.contains { $0.timestamp >= dayStart && $0.timestamp <= now }
            if !loggedToday { return nil }
        }
        let nextAt = isPast ? clock.setTime(clock.addingDays(1, to: now), hour: hour) : at
        let time = formatTime(at)
        return CutoffAnnotation(
            at: at,
            isPast: isPast,
            nextAt: nextAt,
            text: isPast
                ? "Your cutoff was \(time). Next: tomorrow, \(formatTime(nextAt))."
                : "Your cutoff: \(time) today."
        )
    }

    /// Index of the value closest to `x`; `xs` must be ascending.
    public static func nearestIndex(_ xs: [Double], to x: Double) -> Int {
        guard !xs.isEmpty else { return -1 }
        var lo = 0
        var hi = xs.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) >> 1
            if xs[mid] <= x { lo = mid } else { hi = mid }
        }
        return abs(xs[hi] - x) < abs(xs[lo] - x) ? hi : lo
    }

    /// Latest point at or before `now`, the default inspected point.
    public static func nowIndex(_ series: [CaffeinePoint], now: Millis) -> Int {
        var index = 0
        for (i, point) in series.enumerated() where point.t <= now {
            index = i
        }
        return index
    }

    public struct CaffeineInspection: Equatable, Sendable {
        public var t: Millis
        public var isNow: Bool
        public var isFuture: Bool
        /// From the half-life model.
        public var activeMg: Double
        /// Only doses logged today, up to `t`.
        public var loggedMg: Double
        public var loggedCount: Int
        public var alertness: AlertnessEstimate
    }

    public static func inspect(
        point: CaffeinePoint,
        doses: [Dose],
        sleeps: [SleepSession],
        inputs: EstimateInputs,
        dayStart: Millis,
        now: Millis
    ) -> CaffeineInspection {
        let logged = doses.filter { $0.timestamp >= dayStart && $0.timestamp <= point.t && $0.timestamp <= now }
        return CaffeineInspection(
            t: point.t,
            isNow: point.t == now,
            isFuture: point.t > now,
            activeMg: point.mg,
            loggedMg: logged.reduce(0) { $0 + $1.mg },
            loggedCount: logged.count,
            alertness: estimateAlertness(at: point.t, doses: doses, sleeps: sleeps, inputs: inputs)
        )
    }

    public static func describe(_ inspection: CaffeineInspection, formatTime: (Millis) -> String) -> String {
        let time = inspection.isNow ? "Now, \(formatTime(inspection.t))" : formatTime(inspection.t)
        let active = "\(inspection.isFuture ? "projected" : "modeled") active caffeine \(jsRoundInt(inspection.activeMg)) milligrams"
        let logged = inspection.loggedCount == 0
            ? "no doses logged today by then"
            : "\(jsRoundInt(inspection.loggedMg)) milligrams logged today by then in \(inspection.loggedCount) \(inspection.loggedCount == 1 ? "dose" : "doses")"
        let alertness: String
        if case .estimated(let score, _, _) = inspection.alertness {
            alertness = "\(inspection.isFuture ? "projected" : "estimated") alertness \(score)"
        } else {
            alertness = "alertness needs recent main sleep"
        }
        return "\(time): \(active), \(logged), \(alertness)."
    }

    /// Whether today's curve has anything to show: a dose logged today, or
    /// modeled carryover that rounds to at least 1 mg somewhere in the day.
    public static func hasCaffeineSignal(series: [CaffeinePoint], doses: [Dose], dayStart: Millis, dayEnd: Millis) -> Bool {
        doses.contains { $0.timestamp >= dayStart && $0.timestamp < dayEnd } ||
            series.contains { jsRound($0.mg) >= 1 }
    }

    public static let noCaffeineTitle = "No caffeine logged today"
    public static let noCaffeineBody = "Today’s active-caffeine curve appears once you log a dose."

    public static func describeNoCaffeineNote(cutoffText: String?) -> String {
        let base = "Caffeine today. \(noCaffeineTitle), and none is carried over from earlier. \(noCaffeineBody)"
        guard let cutoffText, !cutoffText.isEmpty else { return base }
        return "\(base) \(cutoffText)"
    }

    public static func describeCaffeineDay(
        series: [CaffeinePoint],
        doses: [Dose],
        dayStart: Millis,
        dayEnd: Millis,
        formatTime: (Millis) -> String
    ) -> String {
        let today = doses.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
        let logged = today.isEmpty
            ? "No caffeine logged today."
            : "\(today.count) \(today.count == 1 ? "dose" : "doses") logged today, \(jsRoundInt(today.reduce(0) { $0 + $1.mg })) milligrams total."
        var peak: CaffeinePoint?
        for point in series where peak == nil || point.mg > peak!.mg {
            peak = point
        }
        let shape: String
        if let peak, jsRound(peak.mg) != 0 {
            shape = "Modeled active caffeine peaks at \(jsRoundInt(peak.mg)) milligrams at \(formatTime(peak.t))."
        } else {
            shape = "Modeled active caffeine stays at 0 milligrams."
        }
        return "Active caffeine today chart. \(logged) \(shape)"
    }
}

public struct CaffeinePoint: Equatable, Sendable {
    public var t: Millis
    public var mg: Double
    public var hasDose: Bool

    public init(t: Millis, mg: Double, hasDose: Bool = false) {
        self.t = t
        self.mg = mg
        self.hasDose = hasDose
    }
}

public struct TodayCaffeineSeries: Equatable, Sendable {
    public var series: [CaffeinePoint]
    public var start: Millis
    public var end: Millis
    public var now: Millis

    /// Today's active-caffeine curve: one point per step from local midnight
    /// to the next, plus a point at `now`.
    public static func make(
        doses: [Dose],
        halfLifeHours: Double,
        now: Millis,
        clock: LocalClock,
        stepMinutes: Double = 60
    ) -> TodayCaffeineSeries {
        let (start, end) = clock.dayBounds(now)
        let stepMs = max(1, stepMinutes * minuteMs)
        let count = max(2, jsRoundInt((end - start) / stepMs) + 1)

        var bucketsWithDose = Set<Int>()
        for dose in doses where dose.timestamp >= start && dose.timestamp <= end {
            bucketsWithDose.insert(Int(floor((dose.timestamp - start) / stepMs)))
        }

        var series = (0..<count).map { i -> CaffeinePoint in
            let t = start + Double(i) * stepMs
            return CaffeinePoint(
                t: t,
                mg: Caffeine.activeMg(at: t, doses: doses, halfLifeHours: halfLifeHours),
                hasDose: bucketsWithDose.contains(i)
            )
        }
        if now > start && now < end {
            let bucket = Int(floor((now - start) / stepMs))
            // After any grid point at the same instant, as a stable sort would place it.
            let index = series.firstIndex { $0.t > now } ?? series.endIndex
            series.insert(CaffeinePoint(
                t: now,
                mg: Caffeine.activeMg(at: now, doses: doses, halfLifeHours: halfLifeHours),
                hasDose: bucketsWithDose.contains(bucket)
            ), at: index)
        }
        return TodayCaffeineSeries(series: series, start: start, end: end, now: now)
    }
}
