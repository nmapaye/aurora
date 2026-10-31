import Foundation

/// Insights describes what was recorded over a range. A day with no entries
/// is "no record", never 0 mg; averages count recorded days only; a
/// comparison with the previous period appears only when both periods have
/// enough recorded days.
public enum InsightsRange: Int, Sendable, CaseIterable {
    case week = 7
    case twoWeeks = 14
    case month = 30

    public static let `default`: InsightsRange = .twoWeeks
    public var days: Int { rawValue }
}

public struct InsightsChartPoint: Equatable, Sendable {
    public var date: Millis
    /// `nil` means nothing was recorded that day, not zero intake.
    public var mg: Int?
    public var entries: Int
    public var source: RecordSource?
}

public struct InsightsWindow: Equatable, Sendable {
    public var starts: [Millis]
    public var selected: [Dose]
    public var points: [InsightsChartPoint]
    public var totalMg: Int
    public var recordedDays: Int
    /// Per recorded day.
    public var averageMg: Int?
    public var source: RecordSource?
}

public enum InsightsTrend: Equatable, Sendable {
    public enum Direction: String, Sendable {
        case higher
        case lower
        case similar
    }

    case insufficient(requiredDays: Int, currentDays: Int, previousDays: Int, text: String)
    case compared(direction: Direction, requiredDays: Int, currentDays: Int, previousDays: Int, text: String, detail: String)

    public var text: String {
        switch self {
        case .insufficient(_, _, _, let text), .compared(_, _, _, _, let text, _):
            return text
        }
    }
}

public struct DaypartItem: Equatable, Sendable {
    public var label: String
    public var mg: Double
    public var entries: Int
}

public struct DrinkMixItem: Equatable, Sendable {
    public var label: String
    public var mg: Double
    public var pct: Int
}

public enum ReactionBaseline: String, Sendable {
    case none
    case building
    case established
}

public struct ReactionInsight: Equatable, Sendable {
    public var signal: SignalCardModel
    public var baseline: ReactionBaseline
    public var recentTests: Int
}

public struct InsightsPresentation: Equatable, Sendable {
    public var range: InsightsRange
    public var days: Int
    public var dateRange: String
    public var current: InsightsWindow
    public var previous: InsightsWindow
    public var points: [InsightsChartPoint]
    public var recordedDays: Int
    public var missingDays: Int
    public var headline: String?
    public var period: String
    public var source: RecordSource?
    public var trend: InsightsTrend
    public var dayparts: [DaypartItem]
    public var drinkMix: [DrinkMixItem]
    public var reaction: ReactionInsight
    public var latestRecordedIndex: Int
    public var isEmpty: Bool
    public var accessibilitySummary: String
}

public enum Insights {
    public static let reactionBaselineTests = 3
    public static let reactionBaselineWindowDays = 30
    /// Periods whose averages differ by less than this read as "about the same".
    public static let trendSteadyPct = 10

    /// Half the range, and never fewer than four days.
    public static func trendMinimumDays(_ days: Int) -> Int {
        max(4, Int(ceil(Double(days) / 2)))
    }

    static func normalizeDrink(_ source: String?) -> String {
        guard let source, !source.isEmpty else { return "Other" }
        let value = source.lowercased()
        if value.contains("espresso") || value.contains("drip") || value.contains("brew") || value.contains("coffee") { return "Coffee" }
        if value.contains("tea") || value.contains("matcha") { return "Tea" }
        if value.contains("energy") { return "Energy" }
        if value.contains("pill") { return "Pills" }
        return "Other"
    }

    static func makeWindow(doses: [Dose], starts: [Millis], now: Millis, clock: LocalClock) -> InsightsWindow {
        let allowed = Set(starts.map(clock.dayKey))
        let selected = doses.filter {
            $0.timestamp.isFinite && $0.mg.isFinite && $0.timestamp <= now && allowed.contains(clock.dayKey($0.timestamp))
        }
        var byDay: [Millis: [Dose]] = [:]
        for dose in selected {
            byDay[clock.startOfDay(dose.timestamp), default: []].append(dose)
        }
        let points = starts.map { date -> InsightsChartPoint in
            guard let dayDoses = byDay[date] else {
                return InsightsChartPoint(date: date, mg: nil, entries: 0, source: nil)
            }
            return InsightsChartPoint(
                date: date,
                mg: jsRoundInt(dayDoses.reduce(0) { $0 + $1.mg }),
                entries: dayDoses.count,
                source: RecordSource.of(ids: dayDoses.map(\.id))
            )
        }
        let recordedDays = points.filter { $0.mg != nil }.count
        let totalMg = jsRoundInt(selected.reduce(0) { $0 + $1.mg })
        return InsightsWindow(
            starts: starts,
            selected: selected,
            points: points,
            totalMg: totalMg,
            recordedDays: recordedDays,
            averageMg: recordedDays > 0 ? jsRoundInt(Double(totalMg) / Double(recordedDays)) : nil,
            source: RecordSource.of(ids: selected.map(\.id))
        )
    }

    static func trend(current: InsightsWindow, previous: InsightsWindow, days: Int) -> InsightsTrend {
        let required = trendMinimumDays(days)
        guard current.recordedDays >= required,
              previous.recordedDays >= required,
              let currentAverage = current.averageMg,
              let previousAverage = previous.averageMg,
              previousAverage > 0 else {
            return .insufficient(
                requiredDays: required,
                currentDays: current.recordedDays,
                previousDays: previous.recordedDays,
                text: "A comparison with the previous \(days) days appears once each period has \(required) recorded days. This period has \(current.recordedDays); the previous has \(previous.recordedDays)."
            )
        }
        let pct = jsRoundInt((Double(currentAverage) / Double(previousAverage) - 1) * 100)
        let includesSample = [current.source, previous.source].contains { $0 != nil && $0 != .manual }
        let direction: InsightsTrend.Direction = abs(pct) < trendSteadyPct ? .similar : (pct > 0 ? .higher : .lower)
        let text = direction == .similar
            ? "About the same as the previous \(days) days"
            : "About \(abs(pct))% \(direction.rawValue) than the previous \(days) days"
        return .compared(
            direction: direction,
            requiredDays: required,
            currentDays: current.recordedDays,
            previousDays: previous.recordedDays,
            text: text,
            detail: "\(currentAverage) mg vs \(previousAverage) mg per recorded day · \(current.recordedDays) and \(previous.recordedDays) recorded days\(includesSample ? " · includes Sample Data" : "")"
        )
    }

    static func dayparts(_ doses: [Dose], clock: LocalClock) -> [DaypartItem] {
        var items = ["Morning", "Midday", "Evening", "Late"].map { DaypartItem(label: $0, mg: 0, entries: 0) }
        for dose in doses {
            let hour = clock.hour(dose.timestamp)
            let index = (5..<11).contains(hour) ? 0 : (11..<17).contains(hour) ? 1 : (17..<21).contains(hour) ? 2 : 3
            items[index].mg += dose.mg
            items[index].entries += 1
        }
        return items
    }

    /// A drink's total with its first-seen position, which breaks mg ties.
    /// Explicit types here keep drinkMix fast to type-check on older Xcode.
    private struct DrinkTotal {
        let offset: Int
        let label: String
        let mg: Double

        static func precedes(_ lhs: DrinkTotal, _ rhs: DrinkTotal) -> Bool {
            if lhs.mg != rhs.mg { return lhs.mg > rhs.mg }
            return lhs.offset < rhs.offset
        }
    }

    static func drinkMix(_ doses: [Dose]) -> [DrinkMixItem] {
        var order: [String] = []
        var totals: [String: Double] = [:]
        for dose in doses {
            let label = normalizeDrink(dose.source)
            if totals[label] == nil { order.append(label) }
            totals[label, default: 0] += dose.mg
        }
        var entries: [DrinkTotal] = []
        entries.reserveCapacity(order.count)
        for (offset, label) in order.enumerated() {
            entries.append(DrinkTotal(offset: offset, label: label, mg: totals[label] ?? 0))
        }
        entries.sort(by: DrinkTotal.precedes)
        var total: Double = 0
        for entry in entries { total += entry.mg }
        var items: [DrinkMixItem] = []
        items.reserveCapacity(entries.count)
        for entry in entries {
            let pct: Int = total != 0 ? jsRoundInt(entry.mg / total * 100) : 0
            items.append(DrinkMixItem(label: entry.label, mg: entry.mg, pct: pct))
        }
        return items
    }

    /// The latest test is an observation with its date and source. A
    /// baseline (median of recent tests) appears only once there are enough,
    /// and counts only tests from the same version of the test as the latest
    /// (`VigilanceSession.protocolVersion`), so a new baseline starts with the
    /// 30-second test. A latest test from the earlier version is labeled.
    public static func reactionSignal(
        sessions: [VigilanceSession],
        now: Millis,
        clock: LocalClock,
        text: DateText
    ) -> ReactionInsight {
        let valid = sessions
            .filter { $0.completedAt.isFinite && $0.completedAt <= now }
            .enumerated()
            .sorted { $0.element.completedAt != $1.element.completedAt ? $0.element.completedAt < $1.element.completedAt : $0.offset < $1.offset }
            .map(\.element)
        let id = "insights-reaction-test"
        let label = "Reaction Test"
        let destination = "Take Reaction Test"
        guard let latest = valid.last else {
            return ReactionInsight(
                signal: SignalCardModel(
                    id: id, label: label, period: "No test yet", status: .empty,
                    context: "A \(Vigilance.durationAdjective) test of reaction speed. A personal baseline appears after \(reactionBaselineTests) tests.",
                    destination: destination
                ),
                baseline: .none,
                recentTests: 0
            )
        }
        let windowStart = clock.addingDays(-(reactionBaselineWindowDays - 1), to: clock.startOfDay(now))
        let recent = valid.filter { $0.completedAt >= windowStart && $0.isComparable(with: latest) }
        let source = RecordSource.of(ids: [latest.id]) == .sample ? "Sample Data" : "Recorded"
        let detail = reactionDetail(latest)
        let status: SignalStatus = source == "Sample Data" ? .sample : .observed
        let period = formatSignalDay(latest.completedAt, now: now, clock: clock, text: text)
        if recent.count < reactionBaselineTests {
            return ReactionInsight(
                signal: SignalCardModel(
                    id: id, label: label, period: period, source: source, status: status,
                    value: "\(latest.score)",
                    context: "\(detail) · \(recent.count) of \(reactionBaselineTests) tests toward a baseline (last \(reactionBaselineWindowDays) days)",
                    destination: destination
                ),
                baseline: .building,
                recentTests: recent.count
            )
        }
        let scores = recent.map(\.score).sorted()
        let middle = scores.count / 2
        let median = scores.count % 2 == 1 ? scores[middle] : jsRoundInt((Double(scores[middle - 1]) + Double(scores[middle])) / 2)
        let recentSource = RecordSource.of(ids: recent.map(\.id))
        return ReactionInsight(
            signal: SignalCardModel(
                id: id, label: label, period: period, source: source, status: status,
                value: "\(latest.score)",
                context: "\(detail) · Baseline \(median), median of \(recent.count) tests in the last \(reactionBaselineWindowDays) days\(recentSource?.includesSample == true && recentSource != .sample ? " (includes Sample Data)" : "")",
                destination: destination
            ),
            baseline: .established,
            recentTests: recent.count
        )
    }

    /// "286 ms median", led by the version label for a session
    /// from another version of the test.
    public static func reactionDetail(_ session: VigilanceSession) -> String {
        [session.protocolLabel, session.displayLabel].compactMap { $0 }.joined(separator: " · ")
    }

    public static func describeChartDay(_ point: InsightsChartPoint, text: DateText) -> (title: String, value: String, text: String) {
        let title = text.weekdayDate(point.date)
        let value: String
        if let mg = point.mg {
            value = ["\(mg) mg", plural(point.entries, "entry", "entries"), point.source?.rawValue]
                .compactMap { $0 }
                .joined(separator: " · ")
        } else {
            value = "No record"
        }
        return (title, value, "\(title), \(value)")
    }

    public static func presentation(
        doses: [Dose],
        vigilanceSessions: [VigilanceSession],
        range: InsightsRange = .default,
        now: Millis,
        clock: LocalClock,
        text: DateText
    ) -> InsightsPresentation {
        let days = range.days
        let currentStarts = clock.dayStarts(endingAt: now, days: days)
        let previousEnd = clock.addingDays(-1, to: currentStarts.first ?? now)
        let previousStarts = clock.dayStarts(endingAt: previousEnd, days: days)
        let current = makeWindow(doses: doses, starts: currentStarts, now: now, clock: clock)
        let previousNow = clock.setTime(previousStarts.last ?? previousEnd, hour: 23, minute: 59, second: 59, millisecond: 999)
        let previous = makeWindow(doses: doses, starts: previousStarts, now: previousNow, clock: clock)
        let isEmpty = current.recordedDays == 0
        let dateRange = "\(days) days · \(text.shortDate(currentStarts.first ?? now))–\(text.shortDate(now))"
        let missingDays = days - current.recordedDays
        let headline = current.averageMg.map { "\($0) mg" }
        let period = isEmpty ? dateRange : "Average of \(plural(current.recordedDays, "recorded day")) · \(dateRange)"
        let accessibilitySummary = isEmpty
            ? "Caffeine intake, \(dateRange). No caffeine recorded in this range."
            : "Caffeine intake, \(dateRange). \(headline ?? "") average per recorded day across \(plural(current.recordedDays, "recorded day"))\(current.source.map { ", \($0.rawValue)" } ?? ""). \(plural(missingDays, "day")) with no record."
        var latestRecordedIndex = current.points.count - 1
        for (index, point) in current.points.enumerated() where point.mg != nil {
            latestRecordedIndex = index
        }
        return InsightsPresentation(
            range: range,
            days: days,
            dateRange: dateRange,
            current: current,
            previous: previous,
            points: current.points,
            recordedDays: current.recordedDays,
            missingDays: missingDays,
            headline: headline,
            period: period,
            source: current.source,
            trend: trend(current: current, previous: previous, days: days),
            dayparts: dayparts(current.selected, clock: clock),
            drinkMix: drinkMix(current.selected),
            reaction: reactionSignal(sessions: vigilanceSessions, now: now, clock: clock, text: text),
            latestRecordedIndex: latestRecordedIndex,
            isEmpty: isEmpty,
            accessibilitySummary: accessibilitySummary
        )
    }
}
