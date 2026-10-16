import Foundation

public enum SleepRange: String, Sendable, CaseIterable {
    case week
    case month

    public var days: Int { self == .week ? 7 : 30 }
}

public struct SleepChartPoint: Equatable, Sendable {
    public var date: Millis
    /// `nil` when nothing was recorded that day, never zero.
    public var durationMs: Millis?
}

public struct LastNight: Equatable, Sendable {
    public var session: SleepSession
    public var sessionIDs: [String]
    public var durationMs: Millis
    public var sleepStart: Millis
    public var wakeTime: Millis
    public var targetDifferenceMs: Millis?
}

public struct SleepPresentation: Equatable, Sendable {
    public var days: Int
    public var dateRange: String
    public var points: [SleepChartPoint]
    public var headline: String
    public var recordedNights: Int
    /// Averages recorded days only; a missing day is not a zero-hour night.
    public var averageDurationMs: Millis?
    public var accessibilitySummary: String
    public var lastNight: LastNight?
}

public struct CaffeineImpact: Equatable, Sendable {
    public var qualifyingNights: Int
    public var medianDeltaMin: Int
    public var p10: Int
    public var p90: Int
    public var medianSleepMin: Int
    public var meetsPairedNightGate: Bool
}

public enum SleepModel {
    /// A timing number needs this many nights that each have a sleep episode
    /// and caffeine logged in the 12 hours before it.
    public static let pairedNightsRequired = 14

    /// Time covered by at least one session, overlaps counted once. This
    /// stays separate from `SleepIntervals.merge`: it adds the last interval
    /// as `(duration + end) - start`, as the TypeScript did, and summing
    /// merged lengths would round fractional milliseconds differently. Its
    /// callers pass only sessions `episodes` has already filtered to finite,
    /// non-empty spans.
    static func unionDuration(_ sessions: [SleepSession]) -> Millis {
        let ordered = sessions.sorted { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }
        guard let first = ordered.first else { return 0 }
        var intervalStart = first.start
        var intervalEnd = first.end
        var duration: Millis = 0
        for session in ordered.dropFirst() {
            if session.start <= intervalEnd {
                intervalEnd = max(intervalEnd, session.end)
            } else {
                duration += intervalEnd - intervalStart
                intervalStart = session.start
                intervalEnd = session.end
            }
        }
        return duration + intervalEnd - intervalStart
    }

    /// Episodes whose wake day falls in the range, by the one episode rule.
    static func rangeEpisodes(_ sessions: [SleepSession], range: SleepRange, now: Millis, clock: LocalClock) -> [SleepEpisodeV2] {
        let keys = Set(clock.dayStarts(endingAt: now, days: range.days).map(clock.dayKey))
        return SleepEpisodes.build(sessions, now: now, clock: clock).filter { keys.contains($0.wakeDayKey) }
    }

    /// The middle element by rounded-down index, matching the original.
    static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    static func percentile(_ values: [Int], _ q: Double) -> Int {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let index = Int(clamp(jsRound(q * Double(sorted.count - 1)), 0, Double(sorted.count - 1)))
        return sorted[index]
    }

    public static func sourceLabel(id: String) -> String {
        // Any sample id, as clearing and editing treat it, not only the
        // `demo:sleep:` ids Sample Data generates.
        if RecordID.isSample(id) { return "Sample Data" }
        return RecordID.isHealthSleep(id) ? "Health" : "Manual"
    }

    /// Every source in a merged night, so a partly-sample night never reads
    /// as purely manual.
    public static func episodeSourceLabel(ids: [String]) -> String {
        var labels: [String] = []
        for label in ids.map(sourceLabel) where !labels.contains(label) {
            labels.append(label)
        }
        let order = ["Health", "Manual", "Sample Data"]
        labels.sort { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
        return labels.joined(separator: " and ")
    }

    public static func caffeineImpact(
        sessions: [SleepSession],
        doses: [Dose],
        range: SleepRange,
        now: Millis,
        clock: LocalClock
    ) -> CaffeineImpact {
        // One main sleep per wake day: naps and short sleep never pair.
        let mains = rangeEpisodes(sessions, range: range, now: now, clock: clock).filter { $0.kind == .main }
        let pairs: [(delta: Int, sleep: Int)] = mains.compactMap { night in
            let lastDose = doses
                .filter { $0.timestamp <= night.start && $0.timestamp >= night.start - 12 * hourMs }
                .max { $0.timestamp < $1.timestamp }
            guard let lastDose else { return nil }
            return (
                jsRoundInt((night.start - lastDose.timestamp) / minuteMs),
                jsRoundInt(night.asleepMs / minuteMs)
            )
        }
        let deltas = pairs.map(\.delta)
        return CaffeineImpact(
            qualifyingNights: pairs.count,
            medianDeltaMin: median(deltas),
            p10: percentile(deltas, 0.1),
            p90: percentile(deltas, 0.9),
            medianSleepMin: median(pairs.map(\.sleep)),
            meetsPairedNightGate: pairs.count >= pairedNightsRequired
        )
    }

    public static func presentation(
        sessions: [SleepSession],
        targetSleepHours: Double?,
        range: SleepRange,
        now: Millis,
        clock: LocalClock,
        text: DateText
    ) -> SleepPresentation {
        let days = range.days
        let episodes = rangeEpisodes(sessions, range: range, now: now, clock: clock)
        // Day totals count every episode, naps and short sleep included.
        let totals = SleepEpisodes.asleepByWakeDay(episodes)
        let points = clock.dayStarts(endingAt: now, days: days).map { date -> SleepChartPoint in
            SleepChartPoint(date: date, durationMs: totals[clock.dayKey(date)])
        }
        let recorded = points.compactMap(\.durationMs)
        let average = recorded.isEmpty ? nil : recorded.reduce(0, +) / Double(recorded.count)
        // "Last night" is the latest main sleep only; a nap or a short
        // sample is never compared with the nightly target.
        let latest = episodes
            .filter { $0.kind == .main }
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.end != rhs.element.end
                    ? lhs.element.end > rhs.element.end
                    : lhs.offset < rhs.offset
            }
            .first?.element
        let duration = latest?.asleepMs ?? 0
        let dateRange = "\(days) days ending \(text.shortDate(now))"
        let noun = recorded.count == 1 ? "night" : "nights"
        let accessibilitySummary = recorded.isEmpty
            ? "Time Asleep, \(dateRange). No sleep data is available."
            : "Time Asleep, \(dateRange), \(recorded.count) \(noun) recorded. Latest duration \(formatHoursMinutes(durationMs: recorded.last ?? 0))."

        let lastNight = latest.map { night -> LastNight in
            let newest = night.sessions.enumerated().sorted { lhs, rhs in
                lhs.element.end != rhs.element.end ? lhs.element.end > rhs.element.end : lhs.offset < rhs.offset
            }.first!.element
            return LastNight(
                session: newest,
                sessionIDs: night.sessionIDs,
                durationMs: duration,
                sleepStart: night.start,
                wakeTime: night.end,
                targetDifferenceMs: targetSleepHours.map { duration - $0 * hourMs }
            )
        }

        return SleepPresentation(
            days: days,
            dateRange: dateRange,
            points: points,
            headline: latest == nil ? "No Data" : formatHoursMinutes(durationMs: duration),
            recordedNights: recorded.count,
            averageDurationMs: average,
            accessibilitySummary: accessibilitySummary,
            lastNight: lastNight
        )
    }

    /// The chart readout for one day. A day without sleep says so; it is
    /// never read out as zero.
    public static func describeChartDay(_ point: SleepChartPoint, text: DateText) -> (title: String, value: String, text: String) {
        let title = text.weekdayDate(point.date)
        let value = point.durationMs.map { formatHoursMinutes(durationMs: $0) } ?? "No sleep recorded"
        return (title, value, "\(title), \(value)")
    }

    public static let noTargetText = "No target set"

    /// Without a target there is nothing to compare with, and no reference
    /// is invented.
    public static func describeTargetComparison(durationMs: Millis, targetSleepHours: Double?) -> String {
        guard let targetSleepHours else { return noTargetText }
        let target = formatGap(durationMs: targetSleepHours * hourMs)
        let difference = durationMs - targetSleepHours * hourMs
        if abs(difference) < minuteMs { return "On your \(target) target" }
        return "\(formatGap(durationMs: difference)) \(difference > 0 ? "over" : "under") your \(target) target"
    }

    /// "Today", "Yesterday", "6 days ago", in calendar days.
    public static func describeAge(_ ts: Millis, now: Millis, clock: LocalClock) -> String {
        let day = clock.startOfDay(ts)
        let today = clock.startOfDay(now)
        let days = jsRoundInt((today - day) / dayMs)
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        return "\(days) days ago"
    }

    /// The most recent night in the last seven days.
    public static func recentNightSignal(
        sleeps: [SleepSession],
        targetSleepHours: Double?,
        now: Millis,
        clock: LocalClock,
        text: DateText
    ) -> SignalCardModel {
        let lastNight = presentation(
            sessions: sleeps,
            targetSleepHours: targetSleepHours,
            range: .week,
            now: now,
            clock: clock,
            text: text
        ).lastNight
        guard let lastNight else {
            return SignalCardModel(
                id: "sleep-recent-night",
                label: "Most Recent Sleep",
                period: "Last 7 days",
                status: .empty,
                context: "No sleep recorded in the last 7 days.",
                destination: "Add Sleep"
            )
        }
        let source = episodeSourceLabel(ids: lastNight.sessionIDs)
        let span = "\(text.clockTime(lastNight.sleepStart)) – \(text.clockTime(lastNight.wakeTime))"
        return SignalCardModel(
            id: "sleep-recent-night",
            label: "Most Recent Sleep",
            period: describeAge(lastNight.wakeTime, now: now, clock: clock),
            source: source,
            status: source == "Sample Data" ? .sample : .observed,
            value: formatHoursMinutes(durationMs: lastNight.durationMs),
            context: "\(text.weekdayDate(lastNight.wakeTime)) · \(span) · \(describeTargetComparison(durationMs: lastNight.durationMs, targetSleepHours: targetSleepHours))",
            destination: "Show All Data"
        )
    }

    public static let caffeineTimingLabel = "Caffeine timing before sleep"

    public enum CaffeineTimingSignal: Equatable, Sendable {
        case gathering(pairedNights: Int, required: Int, text: String)
        case observed(
            pairedNights: Int,
            period: String,
            value: String,
            context: String,
            detailRows: [DetailRow],
            accessibilityLabel: String
        )
    }

    public struct DetailRow: Equatable, Sendable {
        public var title: String
        public var value: String
    }

    /// Always the last 30 days; a 7-day window can never reach 14 nights.
    /// Below the gate it reports progress only, never a number.
    public static func caffeineTimingSignal(
        sleeps: [SleepSession],
        doses: [Dose],
        now: Millis,
        clock: LocalClock
    ) -> CaffeineTimingSignal {
        let timing = caffeineImpact(sessions: sleeps, doses: doses, range: .month, now: now, clock: clock)
        let paired = timing.qualifyingNights
        let required = pairedNightsRequired
        guard timing.meetsPairedNightGate else {
            let text = paired == 0
                ? "No nights yet with both sleep and caffeine logged in the 12 hours before it. A typical timing appears after \(required) such nights."
                : "\(paired) of \(required) nights so far with both sleep and caffeine logged in the 12 hours before it. A typical timing appears at \(required)."
            return .gathering(pairedNights: paired, required: required, text: text)
        }
        let value = formatGap(durationMs: Double(timing.medianDeltaMin) * minuteMs)
        let context = "Median time from last logged caffeine to sleep · \(paired) nights"
        let range = "\(formatGap(durationMs: Double(timing.p10) * minuteMs)) – \(formatGap(durationMs: Double(timing.p90) * minuteMs))"
        return .observed(
            pairedNights: paired,
            period: "Last 30 days",
            value: value,
            context: context,
            detailRows: [
                DetailRow(title: "Middle 80% of nights", value: range),
                DetailRow(title: "Nights with both logged", value: "\(paired)"),
            ],
            accessibilityLabel: "\(caffeineTimingLabel), \(value), Last 30 days, \(context)"
        )
    }
}
