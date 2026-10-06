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

/// A night (or nap): samples of one type with gaps under 90 minutes.
public struct SleepEpisode: Equatable, Sendable {
    public var sessions: [SleepSession]
    public var type: SleepType
    public var sleepStart: Millis
    public var wakeTime: Millis
    public var durationMs: Millis
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
    /// Shorter gaps are brief awakenings; 90 minutes starts a new episode.
    public static let episodeGapMs: Millis = 90 * minuteMs
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

    static func episodes(_ sessions: [SleepSession], now: Millis) -> [SleepEpisode] {
        let ordered = sessions
            .filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start && $0.end <= now }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.start != rhs.element.start { return lhs.element.start < rhs.element.start }
                if lhs.element.end != rhs.element.end { return lhs.element.end < rhs.element.end }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        // Types in order of first appearance, as a JavaScript Map keeps them.
        var typeOrder: [SleepType] = []
        var byType: [SleepType: [SleepSession]] = [:]
        for session in ordered {
            if byType[session.type] == nil { typeOrder.append(session.type) }
            byType[session.type, default: []].append(session)
        }
        var groups: [[SleepSession]] = []
        for type in typeOrder {
            var typed: [[SleepSession]] = []
            for session in byType[type] ?? [] {
                if let current = typed.last,
                   let currentEnd = current.map(\.end).max(),
                   session.start - currentEnd < episodeGapMs {
                    typed[typed.count - 1].append(session)
                } else {
                    typed.append([session])
                }
            }
            groups.append(contentsOf: typed)
        }
        return groups.compactMap { sessions in
            guard let first = sessions.first else { return nil }
            return SleepEpisode(
                sessions: sessions,
                type: first.type,
                sleepStart: sessions.map(\.start).min() ?? first.start,
                wakeTime: sessions.map(\.end).max() ?? first.end,
                durationMs: unionDuration(sessions)
            )
        }
    }

    static func rangeEpisodes(_ sessions: [SleepSession], range: SleepRange, now: Millis, clock: LocalClock) -> [SleepEpisode] {
        let keys = Set(clock.dayStarts(endingAt: now, days: range.days).map(clock.dayKey))
        return episodes(sessions, now: now).filter { keys.contains(clock.dayKey($0.wakeTime)) }
    }

    /// Episodes grouped by local wake day, in order of first appearance.
    static func byWakeDay(_ episodes: [SleepEpisode], clock: LocalClock) -> [(key: String, episodes: [SleepEpisode])] {
        var order: [String] = []
        var buckets: [String: [SleepEpisode]] = [:]
        for episode in episodes {
            let key = clock.dayKey(episode.wakeTime)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(episode)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    /// The longest sleep-type episode of a day; ties go to the later wake.
    static func primary(_ episodes: [SleepEpisode]) -> SleepEpisode? {
        episodes
            .filter { $0.type == .sleep }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.durationMs != rhs.element.durationMs { return lhs.element.durationMs > rhs.element.durationMs }
                if lhs.element.wakeTime != rhs.element.wakeTime { return lhs.element.wakeTime > rhs.element.wakeTime }
                return lhs.offset < rhs.offset
            }
            .first?.element
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
        let wakeDays = byWakeDay(rangeEpisodes(sessions, range: range, now: now, clock: clock), clock: clock)
        let pairs: [(delta: Int, sleep: Int)] = wakeDays.compactMap { day in
            guard let night = primary(day.episodes) else { return nil }
            let lastDose = doses
                .filter { $0.timestamp <= night.sleepStart && $0.timestamp >= night.sleepStart - 12 * hourMs }
                .max { $0.timestamp < $1.timestamp }
            guard let lastDose else { return nil }
            return (
                jsRoundInt((night.sleepStart - lastDose.timestamp) / minuteMs),
                jsRoundInt(night.durationMs / minuteMs)
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
        targetSleepHours: Double,
        range: SleepRange,
        now: Millis,
        clock: LocalClock,
        text: DateText
    ) -> SleepPresentation {
        let days = range.days
        let byDay = byWakeDay(rangeEpisodes(sessions, range: range, now: now, clock: clock), clock: clock)
        let lookup = Dictionary(byDay.map { ($0.key, $0.episodes) }, uniquingKeysWith: { first, _ in first })
        let points = clock.dayStarts(endingAt: now, days: days).map { date -> SleepChartPoint in
            guard let episodes = lookup[clock.dayKey(date)] else {
                return SleepChartPoint(date: date, durationMs: nil)
            }
            return SleepChartPoint(date: date, durationMs: unionDuration(episodes.flatMap(\.sessions)))
        }
        let recorded = points.compactMap(\.durationMs)
        let average = recorded.isEmpty ? nil : recorded.reduce(0, +) / Double(recorded.count)
        let latest = byDay
            .compactMap { primary($0.episodes) }
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.wakeTime != rhs.element.wakeTime
                    ? lhs.element.wakeTime > rhs.element.wakeTime
                    : lhs.offset < rhs.offset
            }
            .first?.element
        let duration = latest?.durationMs ?? 0
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
                sessionIDs: night.sessions.map(\.id),
                durationMs: duration,
                sleepStart: night.sleepStart,
                wakeTime: night.wakeTime,
                targetDifferenceMs: duration - targetSleepHours * hourMs
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

    public static func describeTargetComparison(durationMs: Millis, targetSleepHours: Double) -> String {
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
        targetSleepHours: Double,
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
