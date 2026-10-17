import Foundation

/// What the modeled curve says about the day, in plain terms: when modeled
/// energy is highest and lowest today, and how now compares with the same
/// time on recent days. Everything here is model output from recorded sleep,
/// caffeine and time of day; it describes the estimate and suggests nothing.
public struct EnergyOutlook: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public var start: Millis
        public var end: Millis
        public var score: Int
    }

    public enum Comparison: String, Codable, Sendable {
        case higher, lower, similar
    }

    public var peak: Window?
    public var low: Window?
    /// Nil until enough recent days have a modeled score at this time.
    public var comparison: Comparison?
    public var comparedDays: Int
    public var includesSample: Bool

    /// Waking hours searched for highs and lows, local time.
    public static let dayStartHour = 6
    public static let dayEndHour = 22
    /// Points within this many model points of the extreme join its window.
    public static let windowTolerance = 3
    /// A comparison needs this many of the last 7 days to have a score.
    public static let minimumComparedDays = 4
    public static let comparisonDays = 7
    /// Smaller differences read as "about the same".
    public static let similarWithin = 5.0

    public static func make(state: AppState, now: Millis, clock: LocalClock) -> EnergyOutlook {
        let inputs = EstimateInputs(prefs: state.prefs, clock: clock)
        let projection = EnergyProjection.build(now: now, doses: state.doses, sleeps: state.sleeps, inputs: inputs)
        let dayStart = clock.startOfDay(now)
        let from = clock.setTime(dayStart, hour: dayStartHour)
        let to = clock.setTime(dayStart, hour: dayEndHour)
        let today = projection.points.filter { $0.t >= from && $0.t <= to && $0.modeledScore != nil }

        func window(around extreme: EnergyProjection.Point) -> Window? {
            guard let score = extreme.modeledScore, let index = today.firstIndex(where: { $0.t == extreme.t }) else { return nil }
            func close(_ point: EnergyProjection.Point) -> Bool { abs((point.modeledScore ?? -999) - score) <= windowTolerance }
            var first = index, last = index
            while first > 0, close(today[first - 1]) { first -= 1 }
            while last < today.count - 1, close(today[last + 1]) { last += 1 }
            return Window(start: today[first].t, end: today[last].t + EnergyProjection.stepMs, score: score)
        }
        let peak = today.max { ($0.modeledScore ?? 0, -$0.t) < ($1.modeledScore ?? 0, -$1.t) }.flatMap(window)
        let lowPoint = today.min { ($0.modeledScore ?? 0, $0.t) < ($1.modeledScore ?? 0, $1.t) }
        // A flat day has no separate low.
        let low = (lowPoint?.modeledScore ?? 0) + windowTolerance < (peak?.score ?? 0) ? lowPoint.flatMap(window) : nil

        let current = EnergyEstimate.capture(at: now, doses: projection.knownDoses(state.doses), sleeps: projection.knownSleeps(state.sleeps), inputs: inputs)
        // Past days are scored against today's reference, so a usual-sleep
        // reference compares like with like.
        var pastInputs = inputs
        if pastInputs.targetSleepHours == nil { pastInputs.targetSleepHours = current.usualSleep?.hours }
        var past: [Int] = []
        var sample = current.includesSample
        for days in 1...comparisonDays {
            let then = clock.addingDays(-days, to: now)
            let known = EnergyProjection.knownRecords(doses: state.doses, sleeps: state.sleeps, at: then)
            let estimate = EnergyEstimate.capture(at: then, doses: known.doses, sleeps: known.sleeps, inputs: pastInputs)
            if let score = estimate.modeledScore { past.append(score); sample = sample || estimate.includesSample }
        }
        var comparison: Comparison?
        // With neither a target nor usual sleep to compare with, recorded
        // sleep doesn't enter the score, so "about the same as your past
        // week" after a short night would mislead.
        if let score = current.modeledScore, past.count >= minimumComparedDays,
           current.targetSleepHours != nil || current.usualSleep != nil {
            let difference = Double(score) - Double(past.reduce(0, +)) / Double(past.count)
            comparison = difference >= similarWithin ? .higher : (difference <= -similarWithin ? .lower : .similar)
        }
        return EnergyOutlook(
            peak: peak, low: low, comparison: comparison, comparedDays: past.count,
            includesSample: sample || today.contains { $0.includesSample }
        )
    }

    /// One short line per finding, for the card.
    public func lines(text: DateText) -> [String] {
        var lines: [String] = []
        func span(_ window: Window) -> String { "\(text.clockTime(window.start)) – \(text.clockTime(window.end))" }
        if let peak { lines.append("Highest around \(span(peak))") }
        if let low { lines.append("Lowest around \(span(low))") }
        switch comparison {
        case .higher?: lines.append("Higher than your past week at this time")
        case .lower?: lines.append("Lower than your past week at this time")
        case .similar?: lines.append("About the same as your past week at this time")
        case nil: break
        }
        return lines
    }

    public var isEmpty: Bool { peak == nil && low == nil && comparison == nil }
}

extension EnergyProjection {
    func knownDoses(_ doses: [Dose]) -> [Dose] { EnergyProjection.knownRecords(doses: doses, sleeps: [], at: capturedAt).doses }
    func knownSleeps(_ sleeps: [SleepSession]) -> [SleepSession] { EnergyProjection.knownRecords(doses: [], sleeps: sleeps, at: capturedAt).sleeps }
}
