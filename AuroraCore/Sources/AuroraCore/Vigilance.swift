import Foundation

public enum VigilanceRating: String, Codable, Sendable, CaseIterable {
    case sharp = "Sharp"
    case steady = "Steady"
    case slipping = "Slipping"
    case sluggish = "Sluggish"
}

/// One cue of a Reaction Test (protocol 2 and later), kept so a session can
/// be re-scored later.
public struct VigilanceTrial: Codable, Equatable, Hashable, Sendable {
    /// When the cue was drawn, in wall-clock milliseconds.
    public var cueAt: Millis
    /// Touch-down minus `cueAt`. `nil` when no touch came inside the
    /// response window (a missed cue).
    public var reactionMs: Double?
    /// How long after its scheduled time the cue was drawn.
    public var cueLatencyMs: Double?

    public init(cueAt: Millis, reactionMs: Double?, cueLatencyMs: Double? = nil) {
        self.cueAt = cueAt
        self.reactionMs = reactionMs
        self.cueLatencyMs = cueLatencyMs
    }
}

/// A touch that came before the cue, or under `Vigilance.falseStartMs`
/// after it.
public struct VigilanceFalseStart: Codable, Equatable, Hashable, Sendable {
    /// Touch-down, in wall-clock milliseconds.
    public var at: Millis
    /// Milliseconds after the cue was drawn; `nil` when no cue was on screen.
    public var afterCueMs: Double?

    public init(at: Millis, afterCueMs: Double? = nil) {
        self.at = at
        self.afterCueMs = afterCueMs
    }
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
    /// Which test produced this session. 1 is the earlier 60-second test that
    /// timed touch-up; a stored session without the field is version 1.
    /// Scores and baselines only compare sessions of the same version.
    public var protocolVersion: Int
    /// Every cue, in order. Empty for version 1.
    public var trials: [VigilanceTrial]
    /// Every false start, in order. Empty for version 1.
    public var falseStarts: [VigilanceFalseStart]
    /// The `utsname` machine identifier, such as "iPhone17,1". `nil` for
    /// version 1.
    public var deviceModel: String?

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
        rating: VigilanceRating,
        protocolVersion: Int = 1,
        trials: [VigilanceTrial] = [],
        falseStarts: [VigilanceFalseStart] = [],
        deviceModel: String? = nil
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
        self.protocolVersion = protocolVersion
        self.trials = trials
        self.falseStarts = falseStarts
        self.deviceModel = deviceModel
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, completedAt, durationMs, trialCount, validReactionCount, falseStartCount, lapseCount
        case medianReactionMs, meanReactionMs, fastestReactionMs, reactionStdDevMs, score, rating
        case protocolVersion, trials, falseStarts, deviceModel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        startedAt = try c.decode(Millis.self, forKey: .startedAt)
        completedAt = try c.decode(Millis.self, forKey: .completedAt)
        durationMs = try c.decode(Millis.self, forKey: .durationMs)
        trialCount = try c.decode(Int.self, forKey: .trialCount)
        validReactionCount = try c.decode(Int.self, forKey: .validReactionCount)
        falseStartCount = try c.decode(Int.self, forKey: .falseStartCount)
        lapseCount = try c.decode(Int.self, forKey: .lapseCount)
        medianReactionMs = try c.decodeIfPresent(Double.self, forKey: .medianReactionMs)
        meanReactionMs = try c.decodeIfPresent(Double.self, forKey: .meanReactionMs)
        fastestReactionMs = try c.decodeIfPresent(Double.self, forKey: .fastestReactionMs)
        reactionStdDevMs = try c.decodeIfPresent(Double.self, forKey: .reactionStdDevMs)
        score = try c.decode(Int.self, forKey: .score)
        rating = try c.decode(VigilanceRating.self, forKey: .rating)
        protocolVersion = try c.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? 1
        trials = try c.decodeIfPresent([VigilanceTrial].self, forKey: .trials) ?? []
        falseStarts = try c.decodeIfPresent([VigilanceFalseStart].self, forKey: .falseStarts) ?? []
        deviceModel = try c.decodeIfPresent(String.self, forKey: .deviceModel)
    }

    /// Whether this session can be compared with ones from `other`'s test.
    public func isComparable(with other: VigilanceSession) -> Bool {
        protocolVersion == other.protocolVersion
    }

    /// Names a session from another version of the test wherever it is
    /// shown; `nil` for the current test.
    public var protocolLabel: String? {
        Vigilance.protocolLabel(protocolVersion, durationMs: durationMs)
    }

    /// What a hand-edited or damaged store could hold, pulled back to what
    /// the app writes: a version of at least 1, finite trial and false-start
    /// times, no negative reaction times, and a short device name.
    public func normalized() -> VigilanceSession {
        var session = self
        session.protocolVersion = max(1, protocolVersion)
        session.trials = trials.compactMap { trial in
            guard isValidRecordTime(trial.cueAt) else { return nil }
            var kept = trial
            if let reaction = trial.reactionMs, !(reaction.isFinite && reaction >= 0) { kept.reactionMs = nil }
            if let latency = trial.cueLatencyMs, !latency.isFinite { kept.cueLatencyMs = nil }
            return kept
        }
        session.falseStarts = falseStarts.compactMap { falseStart in
            guard isValidRecordTime(falseStart.at) else { return nil }
            var kept = falseStart
            if let after = falseStart.afterCueMs, !after.isFinite { kept.afterCueMs = nil }
            return kept
        }
        if let model = deviceModel {
            let trimmed = String(model.prefix(Vigilance.deviceModelMaxLength))
            session.deviceModel = trimmed.isEmpty ? nil : trimmed
        }
        return session
    }
}

/// The protocol-1 trial outcome, kept to rebuild the earlier test's scores.
public enum VigilanceTrialResult: Equatable, Sendable {
    case valid(reactionMs: Double)
    /// A missed cue (`nil`) or a response of 500 ms or more.
    case lapse(reactionMs: Double?)
}

/// What the test area says after a touch or a missed cue. Each is shown
/// briefly (`Vigilance.feedbackMs`).
public enum VigilanceFeedback: Equatable, Sendable {
    /// A touch before the cue, or under 100 ms after it. `count` is the run's
    /// false starts so far.
    case tooEarly(count: Int)
    /// A response inside the window, valid or slow.
    case reaction(ms: Double)
    /// A touch just after a missed cue's window closed.
    case tooLate
    /// The window closed with no touch.
    case missed
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
    /// When the next cue is due; `nil` while one is on screen.
    public var nextCueAt: Millis?
    /// When the cue on screen was drawn.
    public var cueShownAt: Millis?
    /// When the cue on screen was due, to measure how late it was drawn.
    public var cueScheduledAt: Millis?
    public var trials: [VigilanceTrial]
    public var falseStarts: [VigilanceFalseStart]
    public var feedback: VigilanceFeedback?
    public var feedbackAt: Millis?
    /// Touches before this are the rest of a double tap and are ignored.
    public var ignoreTapsUntil: Millis?
    /// Touches before this, after a missed cue, say "Too late".
    public var lateUntil: Millis?
    /// Set while the run is paused (Close's confirmation is open).
    public var pausedAt: Millis?
    /// Touches ignored as the rest of a double tap. Not scored.
    public var ignoredTapCount: Int

    public init(
        phase: Phase = .instructions,
        startedAt: Millis? = nil,
        endsAt: Millis? = nil,
        nextCueAt: Millis? = nil,
        cueShownAt: Millis? = nil,
        cueScheduledAt: Millis? = nil,
        trials: [VigilanceTrial] = [],
        falseStarts: [VigilanceFalseStart] = [],
        feedback: VigilanceFeedback? = nil,
        feedbackAt: Millis? = nil,
        ignoreTapsUntil: Millis? = nil,
        lateUntil: Millis? = nil,
        pausedAt: Millis? = nil,
        ignoredTapCount: Int = 0
    ) {
        self.phase = phase
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.nextCueAt = nextCueAt
        self.cueShownAt = cueShownAt
        self.cueScheduledAt = cueScheduledAt
        self.trials = trials
        self.falseStarts = falseStarts
        self.feedback = feedback
        self.feedbackAt = feedbackAt
        self.ignoreTapsUntil = ignoreTapsUntil
        self.lateUntil = lateUntil
        self.pausedAt = pausedAt
        self.ignoredTapCount = ignoredTapCount
    }

    public var falseStartCount: Int { falseStarts.count }
    public var cueVisible: Bool { phase == .running && cueShownAt != nil }
}

/// The 30-second Reaction Test (protocol 2) as a pure state machine.
///
/// The screen owns the clock and calls `advance` every display frame with
/// the frame's presentation time, and `tap` with each touch-down's hardware
/// timestamp, both on one millisecond timeline. `randomValue` is in [0, 1)
/// and picks the 1–4 s wait before the next cue.
///
/// - A touch while waiting is a false start: it is counted, says
///   "Too early (n)", and restarts the wait with a new random delay.
/// - A response under 100 ms is a false start too, handled the same way.
///   100 ms to under 400 ms is a valid reaction; 400 ms up to the 1 s window
///   is a lapse with its time; no touch within 1 s is a missed lapse.
/// - A touch within 300 ms of the previous counted touch is the rest of a
///   double tap (or a second finger) and is ignored. This applies after a
///   false start as well as after a response, so one double tap never counts
///   twice.
/// - A touch within 500 ms after a missed cue's window says "Too late" and
///   is not counted: the person reacted to the cue, only too slowly, so it is
///   neither a false start nor a second lapse. It doesn't restart the wait.
/// - A touch inside a cue's window that is processed after the frame clock
///   already closed the window still counts as that cue's response.
/// - A cue on screen at 30 s keeps its full response window.
public enum Vigilance {
    /// The current test. Bump it whenever timing, thresholds or scoring
    /// change in a way that makes scores incomparable.
    public static let protocolVersion = 2
    public static let testDurationMs: Millis = 30_000
    public static let minDelayMs: Millis = 1_000
    public static let maxDelayMs: Millis = 4_000
    public static let responseWindowMs: Millis = 1_000
    public static let falseStartMs: Millis = 100
    public static let lapseMs: Millis = 400
    /// A second touch this soon after a counted one is ignored.
    public static let doubleTapIgnoreMs: Millis = 300
    /// How long after a missed cue's window a touch says "Too late".
    public static let lateGraceMs: Millis = 500
    /// How long the feedback after a touch stays on screen.
    public static let feedbackMs: Millis = 1_000
    static let deviceModelMaxLength = 64

    /// A short label for sessions from another version of the test. The
    /// length comes from the session's `durationMs` when known, because a
    /// 30-second session re-saved by an older build reads as version 1 but
    /// keeps its duration. Without one, version 1 was the 60-second test.
    public static func protocolLabel(_ version: Int, durationMs: Millis? = nil) -> String? {
        switch version {
        case protocolVersion: return nil
        case ..<protocolVersion:
            // Guard the Int conversion against a damaged store (NaN, huge).
            let seconds = durationMs.flatMap { $0.isFinite && $0 >= 500 && $0 <= 3_600_000 ? Int(($0 / 1000).rounded()) : nil } ?? 60
            return "Earlier \(seconds)-second test"
        default: return "Newer test version"
        }
    }

    public static func delayMs(randomValue: Double) -> Millis {
        let normalized = clamp(randomValue, 0, 0.999999)
        return jsRound(minDelayMs + normalized * (maxDelayMs - minDelayMs))
    }

    // MARK: Scoring

    /// Speed anchors in responses per second (1000 / RT in ms): 4.0/s
    /// (250 ms) scores 100 and 2.0/s (500 ms) scores 0.
    public static let bestSpeed: Double = 4.0
    public static let worstSpeed: Double = 2.0

    /// The 0–100 score, led by speed.
    ///
    /// Speed is the mean reciprocal reaction time (mean 1/RT) over every cue:
    /// valid responses and slow ones at their own time, a missed cue at the
    /// 1 s window (1.0/s). Mean 1/RT was chosen over median RT because it is
    /// the most sensitive PVT outcome to sleep loss in the literature (Basner
    /// & Dinges, Sleep 2011), and unlike the median it still moves when a
    /// few responses are slow, while the reciprocal keeps a single long lapse
    /// from swamping the mean the way plain mean RT would.
    ///
    /// The consistency (RT standard deviation) term is gone. Lapses still
    /// count, at a lower weight than before: they lower the mean speed and
    /// take up to 15 points through accuracy, which also takes up to 7.5
    /// points for false starts.
    ///
    /// The rating bands (80/60/40) are kept. Touch-down timing reads about
    /// 70–130 ms faster than the earlier touch-up test, so the speed anchors
    /// moved to 250–500 ms; with them a mean around 280 ms or faster with no
    /// lapses rates Sharp, about 310 ms Steady and about 360 ms Slipping.
    /// Scores are not comparable with the earlier test, which is why every
    /// comparison keeps to one protocol version.
    public static func score(trials: [VigilanceTrial], falseStartCount: Int) -> (score: Int, rating: VigilanceRating) {
        let speeds = trials.map { trial -> Double in
            1000 / max(falseStartMs, min(trial.reactionMs ?? responseWindowMs, responseWindowMs))
        }
        let meanSpeed = speeds.isEmpty ? 0 : speeds.reduce(0, +) / Double(speeds.count)
        let speed = clamp((meanSpeed - worstSpeed) / (bestSpeed - worstSpeed) * 100, 0, 100)
        let attempts = Double(max(1, trials.count + falseStartCount))
        let lapses = Double(trials.filter { ($0.reactionMs ?? responseWindowMs) >= lapseMs }.count)
        let accuracy = clamp(100 - lapses / attempts * 100 - Double(falseStartCount) / attempts * 50, 0, 100)
        let score = Int(clamp(jsRound(speed * 0.85 + accuracy * 0.15), 0, 100))
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

    /// A current-protocol session from a run's cues and false starts. Called
    /// again with stored trials, it re-scores a session.
    public static func buildSession(
        id: String,
        startedAt: Millis,
        completedAt: Millis,
        trials: [VigilanceTrial],
        falseStarts: [VigilanceFalseStart],
        deviceModel: String? = nil
    ) -> VigilanceSession {
        let valid = trials.compactMap { trial -> Double? in
            guard let reaction = trial.reactionMs, reaction >= falseStartMs, reaction < lapseMs else { return nil }
            return reaction
        }
        let lapseCount = trials.filter { ($0.reactionMs ?? responseWindowMs) >= lapseMs }.count
        let scored = score(trials: trials, falseStartCount: falseStarts.count)
        return VigilanceSession(
            id: id,
            startedAt: startedAt,
            completedAt: completedAt,
            durationMs: completedAt - startedAt,
            trialCount: trials.count,
            validReactionCount: valid.count,
            falseStartCount: falseStarts.count,
            lapseCount: lapseCount,
            medianReactionMs: median(valid).map(jsRound),
            meanReactionMs: mean(valid).map(jsRound),
            fastestReactionMs: valid.min(),
            reactionStdDevMs: standardDeviation(valid).map(jsRound),
            score: scored.score,
            rating: scored.rating,
            protocolVersion: protocolVersion,
            trials: trials,
            falseStarts: falseStarts,
            deviceModel: deviceModel
        )
    }

    /// A run that recorded at least one timed response (valid or slow) is
    /// saved; one with only misses and false starts isn't.
    public static func hasTimedResponse(_ state: VigilanceTaskState) -> Bool {
        state.trials.contains { $0.reactionMs != nil }
    }

    // MARK: State machine

    public static func start(at now: Millis, randomValue: Double) -> VigilanceTaskState {
        VigilanceTaskState(
            phase: .running,
            startedAt: now,
            endsAt: now + testDurationMs,
            nextCueAt: now + delayMs(randomValue: randomValue)
        )
    }

    private static func finalize(_ state: VigilanceTaskState) -> VigilanceTaskState {
        var next = state
        next.phase = .complete
        next.cueShownAt = nil
        next.cueScheduledAt = nil
        next.nextCueAt = nil
        return next
    }

    private static func say(_ feedback: VigilanceFeedback, at now: Millis, in state: inout VigilanceTaskState) {
        state.feedback = feedback
        state.feedbackAt = now
    }

    /// Takes the cue off screen and starts a new wait from `from`.
    private static func restartWait(_ state: inout VigilanceTaskState, from: Millis, randomValue: Double) {
        state.cueShownAt = nil
        state.cueScheduledAt = nil
        state.nextCueAt = from + delayMs(randomValue: randomValue)
    }

    /// Moves the run on to `now`: closes a cue's window, shows a due cue
    /// (stamped `cueDrawnAt`, the frame that will show it, when known),
    /// clears old feedback, and ends the run at 30 s.
    public static func advance(
        _ state: VigilanceTaskState,
        at now: Millis,
        cueDrawnAt: Millis? = nil,
        randomValue: Double
    ) -> VigilanceTaskState {
        guard state.phase == .running, state.pausedAt == nil else { return state }
        var next = state

        if let at = next.feedbackAt, now - at >= feedbackMs {
            next.feedback = nil
            next.feedbackAt = nil
        }

        if let cue = next.cueShownAt, now - cue >= responseWindowMs {
            let closed = cue + responseWindowMs
            next.trials.append(VigilanceTrial(cueAt: cue, reactionMs: nil, cueLatencyMs: next.cueScheduledAt.map { cue - $0 }))
            next.lateUntil = closed + lateGraceMs
            say(.missed, at: closed, in: &next)
            restartWait(&next, from: closed, randomValue: randomValue)
        }

        if let ends = next.endsAt, now >= ends, next.cueShownAt == nil {
            return finalize(next)
        }

        if next.cueShownAt == nil, let due = next.nextCueAt, now >= due {
            next.cueShownAt = max(due, cueDrawnAt ?? now)
            next.cueScheduledAt = due
            next.nextCueAt = nil
            next.feedback = nil
            next.feedbackAt = nil
        }
        return next
    }

    /// A touch-down at `now`, from any finger.
    public static func tap(_ state: VigilanceTaskState, at now: Millis, randomValue: Double) -> VigilanceTaskState {
        guard state.phase == .running, state.pausedAt == nil else { return state }
        var next = state
        if let until = state.ignoreTapsUntil, now < until {
            next.ignoredTapCount += 1
            return next
        }
        next.ignoreTapsUntil = now + doubleTapIgnoreMs

        if let cue = state.cueShownAt, now >= cue {
            let reaction = now - cue
            let latency = state.cueScheduledAt.map { cue - $0 }
            if reaction >= responseWindowMs {
                // The frame clock hasn't closed the window yet.
                next.trials.append(VigilanceTrial(cueAt: cue, reactionMs: nil, cueLatencyMs: latency))
                next.lateUntil = nil
                say(.tooLate, at: now, in: &next)
                restartWait(&next, from: cue + responseWindowMs, randomValue: randomValue)
                return next
            }
            if reaction < falseStartMs {
                next.falseStarts.append(VigilanceFalseStart(at: now, afterCueMs: reaction))
                say(.tooEarly(count: next.falseStarts.count), at: now, in: &next)
                restartWait(&next, from: now, randomValue: randomValue)
                return next
            }
            next.trials.append(VigilanceTrial(cueAt: cue, reactionMs: reaction, cueLatencyMs: latency))
            say(.reaction(ms: reaction), at: now, in: &next)
            restartWait(&next, from: now, randomValue: randomValue)
            return next
        }

        // No cue on screen. A touch inside the last cue's window that the
        // frame clock closed first is still that cue's response.
        if let last = state.trials.indices.last, state.trials[last].reactionMs == nil {
            let cue = state.trials[last].cueAt
            let reaction = now - cue
            if reaction >= falseStartMs, reaction < responseWindowMs {
                next.trials[last].reactionMs = reaction
                next.lateUntil = nil
                say(.reaction(ms: reaction), at: now, in: &next)
                return next
            }
            if let lateUntil = state.lateUntil, now >= cue, now < lateUntil {
                next.lateUntil = nil
                say(.tooLate, at: now, in: &next)
                return next
            }
        }

        // A touch while waiting, or before the cue's frame was drawn.
        next.falseStarts.append(VigilanceFalseStart(at: now))
        next.lateUntil = nil
        say(.tooEarly(count: next.falseStarts.count), at: now, in: &next)
        restartWait(&next, from: now, randomValue: randomValue)
        return next
    }

    /// Stops the clock while Close's confirmation is open.
    public static func pause(_ state: VigilanceTaskState, at now: Millis) -> VigilanceTaskState {
        guard state.phase == .running, state.pausedAt == nil else { return state }
        var next = state
        next.pausedAt = now
        return next
    }

    /// Continues a paused run with the time it had left. A cue that was on
    /// screen is withdrawn unscored, since the person was reading the
    /// confirmation, and a new 1–4 s wait starts.
    public static func resume(_ state: VigilanceTaskState, at now: Millis, randomValue: Double) -> VigilanceTaskState {
        guard state.phase == .running, let pausedAt = state.pausedAt else { return state }
        var next = state
        next.pausedAt = nil
        if let ends = next.endsAt { next.endsAt = ends + max(0, now - pausedAt) }
        next.feedback = nil
        next.feedbackAt = nil
        next.lateUntil = nil
        next.ignoreTapsUntil = nil
        restartWait(&next, from: now, randomValue: randomValue)
        if let ends = next.endsAt, let due = next.nextCueAt, due >= ends { next.nextCueAt = ends }
        return next
    }

    // MARK: Protocol 1

    /// The earlier 60-second test's summary numbers.
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

    private static func normalizeDescending(_ value: Double, best: Double, worst: Double) -> Double {
        if value <= best { return 100 }
        if value >= worst { return 0 }
        return jsRound(((worst - value) / (worst - best)) * 100)
    }

    /// How the earlier 60-second test (protocol 1, touch-up timing, 500 ms
    /// lapses) scored: median speed 50%, accuracy 30%, consistency 20%. Kept
    /// so stored version-1 scores can be checked; new runs never use it.
    public static func protocol1Score(_ metrics: Metrics) -> (score: Int, rating: VigilanceRating) {
        let medianForScore = metrics.medianReactionMs ?? 500
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

    /// A protocol-1 session as the earlier test built it.
    public static func protocol1Session(
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
        let scored = protocol1Score(metrics)
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
}
