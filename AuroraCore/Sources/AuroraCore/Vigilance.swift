import Foundation

public enum VigilanceRating: String, Codable, Sendable, CaseIterable {
    case sharp = "Sharp"
    case steady = "Steady"
    case slipping = "Slipping"
    case sluggish = "Sluggish"
}

/// One completed Reaction Test.
public struct VigilanceSession: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var startedAt: Millis
    public var completedAt: Millis
    public var durationMs: Millis
    public var trialCount: Int
    public var validReactionCount: Int
    public var falseStartCount: Int
    public var lapseCount: Int
    public var medianReactionMs: Double?
    public var meanReactionMs: Double?
    public var fastestReactionMs: Double?
    public var reactionStdDevMs: Double?
    public var score: Int
    public var rating: VigilanceRating

    public init(
        id: String,
        startedAt: Millis,
        completedAt: Millis,
        durationMs: Millis,
        trialCount: Int,
        validReactionCount: Int,
        falseStartCount: Int,
        lapseCount: Int,
        medianReactionMs: Double?,
        meanReactionMs: Double?,
        fastestReactionMs: Double?,
        reactionStdDevMs: Double?,
        score: Int,
        rating: VigilanceRating
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
        self.trialCount = trialCount
        self.validReactionCount = validReactionCount
        self.falseStartCount = falseStartCount
        self.lapseCount = lapseCount
        self.medianReactionMs = medianReactionMs
        self.meanReactionMs = meanReactionMs
        self.fastestReactionMs = fastestReactionMs
        self.reactionStdDevMs = reactionStdDevMs
        self.score = score
        self.rating = rating
    }
}

public enum VigilanceTrialResult: Equatable, Sendable {
    case valid(reactionMs: Double)
    /// A missed cue (`nil`) or a response of 500 ms or more.
    case lapse(reactionMs: Double?)
}

public enum VigilanceFeedback: Equatable, Sendable {
    case falseStart
    case missed
    case slow
}

public struct VigilanceTaskState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case instructions
        case running
        case complete
    }

    public var phase: Phase
    public var startedAt: Millis?
    public var endsAt: Millis?
    public var nextCueAt: Millis?
    public var cueShownAt: Millis?
    public var trialResults: [VigilanceTrialResult]
    public var falseStartCount: Int
    public var feedback: VigilanceFeedback?

    public init(
        phase: Phase = .instructions,
        startedAt: Millis? = nil,
        endsAt: Millis? = nil,
        nextCueAt: Millis? = nil,
        cueShownAt: Millis? = nil,
        trialResults: [VigilanceTrialResult] = [],
        falseStartCount: Int = 0,
        feedback: VigilanceFeedback? = nil
    ) {
        self.phase = phase
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.nextCueAt = nextCueAt
        self.cueShownAt = cueShownAt
        self.trialResults = trialResults
        self.falseStartCount = falseStartCount
        self.feedback = feedback
    }
}

/// The 60-second Reaction Test as a pure state machine. The screen owns the
/// timer; it calls `advance` when the next event is due and `tap` on each
/// press. `randomValue` is in [0, 1) and picks the delay before the next cue.
public enum Vigilance {
    public static let testDurationMs: Millis = 60_000
    public static let minDelayMs: Millis = 2_000
    public static let maxDelayMs: Millis = 5_000
    public static let responseWindowMs: Millis = 1_000
    public static let falseStartMs: Millis = 150
    public static let lapseMs: Millis = 500

    public static func delayMs(randomValue: Double) -> Millis {
        let normalized = clamp(randomValue, 0, 0.999999)
        return jsRound(minDelayMs + normalized * (maxDelayMs - minDelayMs))
    }

    private static func normalizeDescending(_ value: Double, best: Double, worst: Double) -> Double {
        if value <= best { return 100 }
        if value >= worst { return 0 }
        return jsRound(((worst - value) / (worst - best)) * 100)
    }

    public struct Metrics: Equatable, Sendable {
        public var trialCount: Int
        public var validReactionCount: Int
        public var falseStartCount: Int
        public var lapseCount: Int
        public var medianReactionMs: Double?
        public var meanReactionMs: Double?
        public var fastestReactionMs: Double?
        public var reactionStdDevMs: Double?

        public init(
            trialCount: Int,
            validReactionCount: Int,
            falseStartCount: Int,
            lapseCount: Int,
            medianReactionMs: Double?,
            meanReactionMs: Double?,
            fastestReactionMs: Double?,
            reactionStdDevMs: Double?
        ) {
            self.trialCount = trialCount
            self.validReactionCount = validReactionCount
            self.falseStartCount = falseStartCount
            self.lapseCount = lapseCount
            self.medianReactionMs = medianReactionMs
            self.meanReactionMs = meanReactionMs
            self.fastestReactionMs = fastestReactionMs
            self.reactionStdDevMs = reactionStdDevMs
        }
    }

    public static func score(_ metrics: Metrics) -> (score: Int, rating: VigilanceRating) {
        let medianForScore = metrics.medianReactionMs ?? lapseMs
        let stdDevForScore = metrics.reactionStdDevMs ?? 180
        let totalAttempts = Double(max(1, metrics.trialCount + metrics.falseStartCount))
        let lapseRate = Double(metrics.lapseCount) / totalAttempts
        let falseStartRate = Double(metrics.falseStartCount) / totalAttempts

        let speed = normalizeDescending(medianForScore, best: 220, worst: 500)
        let consistency = normalizeDescending(stdDevForScore, best: 40, worst: 180)
        let accuracy = clamp(jsRound(100 - lapseRate * 120 - falseStartRate * 60), 0, 100)
        let score = Int(clamp(jsRound(speed * 0.5 + accuracy * 0.3 + consistency * 0.2), 0, 100))
        return (score, rating(for: score))
    }

    public static func rating(for score: Int) -> VigilanceRating {
        if score >= 80 { return .sharp }
        if score >= 60 { return .steady }
        if score >= 40 { return .slipping }
        return .sluggish
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Population standard deviation.
    private static func standardDeviation(_ values: [Double]) -> Double? {
        guard let avg = mean(values) else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - avg) * ($1 - avg) } / Double(values.count)
        return variance.squareRoot()
    }

    public static func buildSession(
        id: String,
        startedAt: Millis,
        completedAt: Millis,
        trialResults: [VigilanceTrialResult],
        falseStartCount: Int
    ) -> VigilanceSession {
        let validReactions = trialResults.compactMap { result -> Double? in
            if case .valid(let reaction) = result { return reaction }
            return nil
        }
        let lapseCount = trialResults.filter { if case .lapse = $0 { true } else { false } }.count
        let metrics = Metrics(
            trialCount: trialResults.count,
            validReactionCount: validReactions.count,
            falseStartCount: falseStartCount,
            lapseCount: lapseCount,
            medianReactionMs: median(validReactions).map(jsRound),
            meanReactionMs: mean(validReactions).map(jsRound),
            fastestReactionMs: validReactions.min(),
            reactionStdDevMs: standardDeviation(validReactions).map(jsRound)
        )
        let scored = score(metrics)
        return VigilanceSession(
            id: id,
            startedAt: startedAt,
            completedAt: completedAt,
            durationMs: completedAt - startedAt,
            trialCount: metrics.trialCount,
            validReactionCount: metrics.validReactionCount,
            falseStartCount: metrics.falseStartCount,
            lapseCount: metrics.lapseCount,
            medianReactionMs: metrics.medianReactionMs,
            meanReactionMs: metrics.meanReactionMs,
            fastestReactionMs: metrics.fastestReactionMs,
            reactionStdDevMs: metrics.reactionStdDevMs,
            score: scored.score,
            rating: scored.rating
        )
    }

    public static func start(at now: Millis, randomValue: Double) -> VigilanceTaskState {
        VigilanceTaskState(
            phase: .running,
            startedAt: now,
            endsAt: now + testDurationMs,
            nextCueAt: now + delayMs(randomValue: randomValue)
        )
    }

    private static func scheduleNextCue(
        _ state: VigilanceTaskState,
        at now: Millis,
        randomValue: Double,
        feedback: VigilanceFeedback?
    ) -> VigilanceTaskState {
        var next = state
        next.cueShownAt = nil
        next.nextCueAt = now + delayMs(randomValue: randomValue)
        next.feedback = feedback
        return next
    }

    private static func finalize(_ state: VigilanceTaskState) -> VigilanceTaskState {
        var next = state
        next.phase = .complete
        next.cueShownAt = nil
        next.nextCueAt = nil
        return next
    }

    public static func advance(_ state: VigilanceTaskState, at now: Millis, randomValue: Double) -> VigilanceTaskState {
        guard state.phase == .running else { return state }

        if let endsAt = state.endsAt, now >= endsAt {
            if state.cueShownAt != nil {
                var next = state
                next.trialResults.append(.lapse(reactionMs: nil))
                next.feedback = .missed
                return finalize(next)
            }
            return finalize(state)
        }

        if state.cueShownAt == nil, let nextCueAt = state.nextCueAt, now >= nextCueAt {
            var next = state
            next.cueShownAt = nextCueAt
            next.nextCueAt = nil
            next.feedback = nil
            return next
        }

        if let cueShownAt = state.cueShownAt, now - cueShownAt >= responseWindowMs {
            var next = state
            next.trialResults.append(.lapse(reactionMs: nil))
            return scheduleNextCue(next, at: now, randomValue: randomValue, feedback: .missed)
        }

        return state
    }

    public static func tap(_ state: VigilanceTaskState, at now: Millis, randomValue: Double) -> VigilanceTaskState {
        guard state.phase == .running else { return state }

        guard let cueShownAt = state.cueShownAt else {
            var next = state
            next.falseStartCount += 1
            next.feedback = .falseStart
            return next
        }

        let reaction = now - cueShownAt
        var next = state
        if reaction < falseStartMs {
            next.falseStartCount += 1
            return scheduleNextCue(next, at: now, randomValue: randomValue, feedback: .falseStart)
        }
        if reaction >= lapseMs {
            next.trialResults.append(.lapse(reactionMs: reaction))
            return scheduleNextCue(next, at: now, randomValue: randomValue, feedback: .slow)
        }
        next.trialResults.append(.valid(reactionMs: reaction))
        return scheduleNextCue(next, at: now, randomValue: randomValue, feedback: nil)
    }
}
