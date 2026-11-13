// RESEARCH / UNVALIDATED. Compiled only when AURORA_RESEARCH_KSS is defined
// (Package.swift defines it for Debug builds only), never referenced by the
// app, and never shown in UI. See Research/CITATIONS.md.
#if AURORA_RESEARCH_KSS
import Foundation

/// Predicted Karolinska Sleepiness Scale (KSS) from the ORIGINAL full
/// Three-Process Model of alertness regulation (TPM; Åkerstedt & Folkard).
///
/// Equations and every constant are transcribed from Ingre et al. (2014),
/// "Validating and Extending the Three Process Model of Alertness in Airline
/// Operations", PLoS ONE 9(10): e108679, eqs 1.1–1.9,
/// DOI 10.1371/journal.pone.0108679 (CC BY 4.0; co-author T. Åkerstedt),
/// which restates the parameters estimated in Åkerstedt & Folkard (1990,
/// Sleep '90 pp. 310–313; no DOI) and published in Åkerstedt, Folkard &
/// Portin (2004), Aviat Space Environ Med 75(3 Suppl):A75–83 (no DOI;
/// PMID 15018268). The sleep-recovery "brake" is Åkerstedt et al. (2008),
/// DOI 10.1080/07420520802110613. KSS itself: Åkerstedt & Gillberg (1990),
/// DOI 10.3109/00207459008994241.
///
/// This is a line-for-line Swift port of `website/research/tpm-kss.ts`
/// (same equations, same input rules, same refusals) and is cross-checked
/// against it in `KSSModelTests`.
///
/// Scope, stated plainly:
/// - It is NOT the improved fitted variants from Ingre 2014 (e.g. S+C only,
///   chronotype-adjusted phase). It is the original full S+C+U+W model.
/// - Caffeine is NOT part of the formula. No published, validated caffeine
///   term for TPM→KSS was found, so none is invented. Any recorded positive
///   dose in the window, or an unknown caffeine history, returns
///   `.notSupported(.caffeineEffectNotValidated / .unknownCaffeineHistory)`.
///   This is an open question for Prof. Åkerstedt.
/// - Output is a population-default model value on the KSS axis, not a
///   rating the person gave and not a validated individual prediction.
///   Never present it to people, never mix it with self-reported KSS.
public enum KSSModel {
    public static let version = "tpm-original-full-ingre2014-eq1.1-1.9/research-unvalidated"
    public static let validationStatus = "Research only. Equation reproduction; no independent clinical, individual, or caffeine validation."

    /// Constants of the original full TPM. Each value: Ingre et al. 2014,
    /// DOI 10.1371/journal.pone.0108679, section "The model equations".
    public struct Parameters: Equatable, Sendable {
        /// ha: upper asymptote of S (eq 1.1–1.4).
        public var upperAsymptote: Double
        /// la: lower asymptote of S (eq 1.1).
        public var lowerAsymptote: Double
        /// d: wake decay rate of S, per hour (eq 1.1).
        public var wakeDecayRate: Double
        /// bl: brake level of S' (eq 1.3–1.5). Åkerstedt et al. 2008,
        /// DOI 10.1080/07420520802110613, as restated by Ingre 2014.
        public var brakeLevel: Double
        /// g = ln((ha − 14.0)/(ha − 7.96)) / 8 ≈ −0.3813 per hour: sleep
        /// recovery rate (eq 1.2–1.5). The 14.0, 7.96 and 8 are part of the
        /// published definition of g.
        public var sleepRecoveryRate: Double
        /// Wc: sleep inertia amplitude at waking (eq 1.6).
        public var inertiaAmplitude: Double
        /// Wd: sleep inertia recovery rate, per hour (eq 1.6).
        public var inertiaRecoveryRate: Double
        /// Cm, Ca: circadian mesor and amplitude, 24 h period (eq 1.7).
        public var circadianMesor: Double
        public var circadianAmplitude: Double
        /// Um, Ua: ultradian mesor and amplitude, 12 h period, phase p + 3 h (eq 1.8).
        public var ultradianMesor: Double
        public var ultradianAmplitude: Double
        public var ultradianPhaseOffsetHours: Double
        /// p: default circadian phase in hours (eq 1.7–1.8).
        public var defaultPhaseHours: Double
        /// a, b: KSS transfer, KSS = a + b·(S + C + U + W) (eq 1.9).
        public var kssIntercept: Double
        public var kssSlope: Double
        /// Default sleep-generator threshold for falling asleep, S + C + U = 8.38
        /// (Ingre 2014, "sleep generator"). Used ONLY to initialise S at the
        /// start of the first recorded sleep, exactly as tpm-kss.ts does. This
        /// is an assumption, not the person's real prior sleep pressure.
        public var sleepEntryThreshold: Double

        public static let original = Parameters(
            upperAsymptote: 14.3,
            lowerAsymptote: 2.4,
            wakeDecayRate: -0.0353,
            brakeLevel: 12.2,
            sleepRecoveryRate: log((14.3 - 14.0) / (14.3 - 7.96)) / 8,
            inertiaAmplitude: -5.72,
            inertiaRecoveryRate: -1.51,
            circadianMesor: 0,
            circadianAmplitude: 2.5,
            ultradianMesor: -0.5,
            ultradianAmplitude: 0.5,
            ultradianPhaseOffsetHours: 3,
            defaultPhaseHours: 16.8,
            kssIntercept: 10.6,
            kssSlope: -0.6,
            sleepEntryThreshold: 8.38
        )
    }

    public enum SegmentState: String, Codable, Sendable { case sleep, awake, unknown }

    /// One contiguous, timestamped interval. Awake must be confirmed: a gap in
    /// sleep records is not evidence of wake (use `.unknown`).
    public struct Segment: Codable, Equatable, Sendable {
        public var state: SegmentState
        public var start: Millis
        public var end: Millis
        public init(state: SegmentState, start: Millis, end: Millis) {
            self.state = state; self.start = start; self.end = end
        }
    }

    public struct TimedCaffeine: Codable, Equatable, Sendable {
        public var at: Millis
        public var mg: Double
        public init(at: Millis, mg: Double) { self.at = at; self.mg = mg }
    }

    /// `nil` means caffeine history is unknown (refused).
    public struct CaffeineHistory: Codable, Equatable, Sendable {
        public var complete: Bool
        public var doses: [TimedCaffeine]
        public init(complete: Bool, doses: [TimedCaffeine]) { self.complete = complete; self.doses = doses }
    }

    public struct Input: Equatable, Sendable {
        public var at: Millis
        public var timeZone: TimeZone?
        public var phaseHours: Double
        public var history: [Segment]
        public var caffeine: CaffeineHistory?
        public init(at: Millis, timeZone: TimeZone?, phaseHours: Double = Parameters.original.defaultPhaseHours, history: [Segment], caffeine: CaffeineHistory?) {
            self.at = at; self.timeZone = timeZone; self.phaseHours = phaseHours
            self.history = history; self.caffeine = caffeine
        }
    }

    /// Same reasons, same order as tpm-kss.ts `evaluateResearchBaseline`.
    public enum Refusal: String, Codable, Sendable {
        case invalidQuery = "invalid-query"
        case invalidTimeZone = "invalid-time-zone"
        case missingSleepHistory = "missing-sleep-history"
        case invalidHistory = "invalid-history"
        case unknownSleepWakeState = "unknown-sleep-wake-state"
        case gapOrOverlap = "gap-or-overlap"
        case splitEpisode = "split-episode"
        case incompleteHistory = "incomplete-history"
        case needsTwoSleepEpisodes = "needs-two-sleep-episodes"
        case outsideStudyWakeWindow = "outside-study-wake-window"
        case unknownCaffeineHistory = "unknown-caffeine-history"
        case invalidCaffeineHistory = "invalid-caffeine-history"
        case caffeineEffectNotValidated = "caffeine-effect-not-validated"
    }

    public struct Components: Equatable, Sendable {
        /// Process S (homeostatic), C (circadian), U (ultradian), W (inertia).
        public var homeostatic: Double
        public var circadian: Double
        public var ultradian: Double
        public var inertia: Double
    }

    public struct Prediction: Equatable, Sendable {
        /// a + b·(S+C+U+W), unclamped.
        public var rawKSS: Double
        /// rawKSS clamped to the KSS range 1…9.
        public var boundedKSS: Double
        public var components: Components
        public var hoursAwake: Double
        public let modelVersion = KSSModel.version
        public let validation = KSSModel.validationStatus
        public let caffeine = "Not modeled. No validated TPM caffeine term; open question for Prof. Åkerstedt."
    }

    public enum Result: Equatable, Sendable {
        case researchPrediction(Prediction)
        case notSupported(Refusal)

        public var prediction: Prediction? {
            if case .researchPrediction(let p) = self { return p }
            return nil
        }
        public var refusal: Refusal? {
            if case .notSupported(let r) = self { return r }
            return nil
        }
    }

    /// Study selection window used by tpm-kss.ts: query within 16 h of waking.
    public static let maximumHoursAwake: Double = 16

    // MARK: Equations

    /// Eq 1.1: S = la + (sw − la)·exp(d·taw).
    public static func wakeState(_ level: Double, hours: Double, _ p: Parameters = .original) -> Double {
        p.lowerAsymptote + (level - p.lowerAsymptote) * exp(p.wakeDecayRate * hours)
    }

    /// Eq 1.2 (original 1990 recovery): S' = ha − (ha − ss)·exp(g·tas).
    public static func originalSleepState(_ level: Double, hours: Double, _ p: Parameters = .original) -> Double {
        p.upperAsymptote - (p.upperAsymptote - level) * exp(p.sleepRecoveryRate * hours)
    }

    /// Eq 1.3–1.5 (with brake): below bl, S'1 = ss + tas·g·(bl − ha) until
    /// bt = (bl − ss)/(g·(bl − ha)); then S'2 = ha − (ha − bl)·exp(g·(tas − bt)).
    public static func sleepState(_ level: Double, hours: Double, _ p: Parameters = .original) -> Double {
        if level >= p.brakeLevel { return originalSleepState(level, hours: hours, p) }
        let rate = p.sleepRecoveryRate * (p.brakeLevel - p.upperAsymptote)
        let brakeAt = (p.brakeLevel - level) / rate
        return hours <= brakeAt
            ? level + rate * hours
            : originalSleepState(p.brakeLevel, hours: hours - brakeAt, p)
    }

    /// Eq 1.7 and 1.8.
    public static func clockTerms(localHour: Double, phaseHours: Double, _ p: Parameters = .original) -> (circadian: Double, ultradian: Double) {
        let c = p.circadianMesor + p.circadianAmplitude * cos((2 * Double.pi / 24) * (localHour - phaseHours))
        let u = p.ultradianMesor + p.ultradianAmplitude * cos((2 * Double.pi / 12) * (localHour - phaseHours - p.ultradianPhaseOffsetHours))
        return (c, u)
    }

    /// Eq 1.6: W = Wc·exp(Wd·taw).
    public static func inertia(hoursAwake: Double, _ p: Parameters = .original) -> Double {
        p.inertiaAmplitude * exp(p.inertiaRecoveryRate * hoursAwake)
    }

    /// Eq 1.9: KSS = a + b·(S + C + U + W).
    public static func kss(_ c: Components, _ p: Parameters = .original) -> Double {
        p.kssIntercept + p.kssSlope * (c.homeostatic + c.circadian + c.ultradian + c.inertia)
    }

    /// Local wall-clock hour (whole seconds, like Intl.DateTimeFormat in tpm-kss.ts).
    static func localHour(_ at: Millis, _ zone: TimeZone) -> Double {
        let seconds = (at / 1000).rounded(.down)
        let offset = Double(zone.secondsFromGMT(for: Date(timeIntervalSince1970: seconds)))
        var local = (seconds + offset).truncatingRemainder(dividingBy: 86_400)
        if local < 0 { local += 86_400 }
        return local / 3600
    }

    // MARK: Prediction

    public static func predict(_ input: Input, parameters p: Parameters = .original) -> Result {
        guard input.at.isFinite, input.phaseHours.isFinite, input.phaseHours >= 0, input.phaseHours < 24 else {
            return .notSupported(.invalidQuery)
        }
        guard let zone = input.timeZone else { return .notSupported(.invalidTimeZone) }
        let history = input.history.sorted { $0.start < $1.start }
        guard !history.isEmpty else { return .notSupported(.missingSleepHistory) }
        for (i, s) in history.enumerated() {
            guard s.start.isFinite, s.end.isFinite, s.end > s.start, s.end <= input.at else {
                return .notSupported(.invalidHistory)
            }
            if s.state == .unknown { return .notSupported(.unknownSleepWakeState) }
            if i > 0, history[i - 1].end != s.start { return .notSupported(.gapOrOverlap) }
            if i > 0, history[i - 1].state == s.state { return .notSupported(.splitEpisode) }
        }
        guard history[0].state == .sleep, history[history.count - 1].end == input.at else {
            return .notSupported(.incompleteHistory)
        }
        let sleeps = history.filter { $0.state == .sleep }
        guard sleeps.count >= 2, let lastSleep = sleeps.last else { return .notSupported(.needsTwoSleepEpisodes) }
        let hoursAwake = (input.at - lastSleep.end) / hourMs
        if hoursAwake > maximumHoursAwake { return .notSupported(.outsideStudyWakeWindow) }
        guard let caffeine = input.caffeine, caffeine.complete else { return .notSupported(.unknownCaffeineHistory) }
        for dose in caffeine.doses {
            guard dose.at.isFinite, dose.mg.isFinite, dose.mg >= 0, dose.at >= history[0].start, dose.at <= input.at else {
                return .notSupported(.invalidCaffeineHistory)
            }
        }
        // Deliberately no invented washout window or KSS-per-mg coefficient.
        if caffeine.doses.contains(where: { $0.mg > 0 }) { return .notSupported(.caffeineEffectNotValidated) }

        let initial = clockTerms(localHour: localHour(history[0].start, zone), phaseHours: input.phaseHours, p)
        var s = p.sleepEntryThreshold - initial.circadian - initial.ultradian
        for seg in history {
            let hours = (seg.end - seg.start) / hourMs
            s = seg.state == .sleep ? sleepState(s, hours: hours, p) : wakeState(s, hours: hours, p)
        }
        let clock = clockTerms(localHour: localHour(input.at, zone), phaseHours: input.phaseHours, p)
        let components = Components(homeostatic: s, circadian: clock.circadian, ultradian: clock.ultradian, inertia: inertia(hoursAwake: hoursAwake, p))
        let raw = kss(components, p)
        return .researchPrediction(Prediction(rawKSS: raw, boundedKSS: min(9, max(1, raw)), components: components, hoursAwake: hoursAwake))
    }

    // MARK: Adapter from Aurora sleep records

    /// Builds alternating segments from recorded sleep, from the first sleep
    /// start to `at`. Overlapping or touching sleep sessions (any type) are
    /// merged; brief awakenings between fragments stay as separate wake
    /// segments, so fragmented sleep is modeled as the equations define it.
    ///
    /// Time between recorded sleeps is `.awake` only when the caller asserts
    /// the record is complete (`unrecordedTimeIsConfirmedAwake`); otherwise it
    /// is `.unknown` and `predict` refuses. No missing night is imputed.
    public static func segments(fromSleep sleeps: [SleepSession], until at: Millis, unrecordedTimeIsConfirmedAwake: Bool) -> [Segment] {
        let intervals = sleeps
            .filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start && $0.start < at }
            .map { (start: $0.start, end: min($0.end, at)) }
            .sorted { $0.start < $1.start }
        var merged: [(start: Millis, end: Millis)] = []
        for iv in intervals {
            if let last = merged.last, iv.start <= last.end {
                merged[merged.count - 1].end = max(last.end, iv.end)
            } else {
                merged.append(iv)
            }
        }
        let between: SegmentState = unrecordedTimeIsConfirmedAwake ? .awake : .unknown
        var out: [Segment] = []
        for (i, iv) in merged.enumerated() {
            if i > 0 { out.append(Segment(state: between, start: merged[i - 1].end, end: iv.start)) }
            out.append(Segment(state: .sleep, start: iv.start, end: iv.end))
        }
        if let last = merged.last, last.end < at {
            out.append(Segment(state: between, start: last.end, end: at))
        }
        return out
    }
}
#endif
