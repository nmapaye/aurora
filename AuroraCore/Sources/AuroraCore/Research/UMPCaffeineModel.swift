// RESEARCH / UNVALIDATED. Compiled only when AURORA_RESEARCH_CAFFEINE is
// defined. Nothing defines it by default: not Package.swift, not the app,
// not Debug, not Release. Build it explicitly with
//   swift test -Xswiftc -DAURORA_RESEARCH_CAFFEINE
// Never referenced by the app and never shown in UI.
// Citations: docs/research/ump-caffeine/CITATIONS.md
// Flagged (unpublished or ambiguous) items: docs/research/ump-caffeine/FLAGGED.md
#if AURORA_RESEARCH_CAFFEINE
import Foundation

/// Unified Model of Performance (UMP) with the caffeine pharmacodynamic
/// factor, implemented only from the published equations:
///
/// - Ramakrishnan S, Wesensten NJ, Kamimori GH, Moon JE, Balkin TJ,
///   Reifman J. "A unified model of performance for predicting the effects
///   of sleep and caffeine." Sleep 2016;39(10):1827–1841,
///   doi:10.5665/sleep.6164 ("2016b"), Table 2 Eqs 1–6 and Table 3.
/// - Ramakrishnan S, Wesensten NJ, Balkin TJ, Reifman J. "A unified model
///   of performance: validation of its predictions across different
///   sleep/wake schedules." Sleep 2016;39(1):249–262, doi:10.5665/sleep.5358
///   ("2016a"), Table 2 Eqs 1–5 and the −0.11 debt floor (p. 250).
/// - Rajdev P et al. J Theor Biol 2013;331:66–77,
///   doi:10.1016/j.jtbi.2013.04.013 (sleep-debt filter, Eqs 5a–6b).
/// - Ramakrishnan S et al. J Theor Biol 2014;358:11–24,
///   doi:10.1016/j.jtbi.2014.05.017 (gPD = 1 before the first dose, Eq 6).
///
/// Scope, stated plainly:
/// - Output is the model's group-average PVT impairment (10-min PVT lapses,
///   or mean RT in ms with the mean-RT parameter set). It is not a person's
///   alertness, not a KSS value, and not validated for any individual.
/// - Time `t` is "model hours" exactly as in Eq 3 of 2016b. The papers do not
///   state the clock origin of `t`, so no clock-time or Date API is offered
///   (FLAGGED F1). Callers give the schedule in model hours from t = 0.
/// - One caffeine dose only. The papers defer repeated doses to the 2014
///   extension, which is written for the gPD form without absorption; how
///   it combines with the absorption form used here is not published in the
///   sources read (FLAGGED F2). More than one dose throws.
/// - Only the two absorption rates the paper gives (capsule, gum). No ka for
///   coffee, tea or energy drinks is published in the sources (FLAGGED F3).
/// - Independent of the KSS Three-Process Model research formula, which
///   stays caffeine-free. Nothing here is shared with it.
public enum UMPCaffeineModel {
    public static let version = "ump-caffeine-ramakrishnan2016b-table3/research-unvalidated"
    public static let validationStatus = "Research only. Equation transcription with checks against the few numbers the papers state; no curve-level parity (papers give figures only), no individual validation."

    /// The twelve UMP parameters of 2016b Table 3 plus the fixed structural
    /// constants. See docs/research/ump-caffeine/CITATIONS.md for each value.
    public struct Parameters: Equatable, Sendable {
        /// U: upper asymptote of process S (2016b Table 3).
        public var upperAsymptote: Double
        /// τw: wake time constant of S, hours (2016b Table 3).
        public var wakeTimeConstantHours: Double
        /// τs: sleep time constant of S, hours (2016b Table 3).
        public var sleepTimeConstantHours: Double
        /// S0: initial value of S (2016b Table 3).
        public var initialS: Double
        /// κ: circadian amplitude (2016b Table 3).
        public var circadianAmplitude: Double
        /// φ: circadian phase, hours (2016b Table 3). Clock origin of t: FLAGGED F1.
        public var circadianPhaseHours: Double
        /// τLA: sleep-debt time constant, hours (2016b Table 3 gives 7.0 d; ×24).
        public var debtTimeConstantHours: Double
        /// L0: initial value of the lower asymptote L (2016b Table 3).
        public var initialL: Double
        /// Minimum sleep debt; L never falls below this × U (2016a p. 250; 2016b Eq 5).
        /// `nil` disables the floor (the original 2013 model, debt range −2…1).
        public var debtFloor: Double?
        /// a1…a5: harmonic amplitudes of process C (2016b Table 2, Eq 3).
        public var harmonics: [Double]
        /// τ: circadian period, hours (Eq 3 says "~24 h"; 2014 §2.3 fixes τ = 24 h).
        public var circadianPeriodHours: Double
        /// M0: caffeine amplitude slope, per gram (2016b Table 3).
        public var amplitudeSlopePerGram: Double
        /// k0: basal caffeine-effect elimination rate, per hour (2016b Table 3).
        public var basalEliminationPerHour: Double
        /// z: dose decay constant of kc, per gram (2016b Table 3).
        public var doseDecayPerGram: Double

        public init(upperAsymptote: Double, wakeTimeConstantHours: Double, sleepTimeConstantHours: Double,
                    initialS: Double, circadianAmplitude: Double, circadianPhaseHours: Double,
                    debtTimeConstantHours: Double, initialL: Double, debtFloor: Double?,
                    harmonics: [Double], circadianPeriodHours: Double, amplitudeSlopePerGram: Double,
                    basalEliminationPerHour: Double, doseDecayPerGram: Double) {
            self.upperAsymptote = upperAsymptote
            self.wakeTimeConstantHours = wakeTimeConstantHours
            self.sleepTimeConstantHours = sleepTimeConstantHours
            self.initialS = initialS
            self.circadianAmplitude = circadianAmplitude
            self.circadianPhaseHours = circadianPhaseHours
            self.debtTimeConstantHours = debtTimeConstantHours
            self.initialL = initialL
            self.debtFloor = debtFloor
            self.harmonics = harmonics
            self.circadianPeriodHours = circadianPeriodHours
            self.amplitudeSlopePerGram = amplitudeSlopePerGram
            self.basalEliminationPerHour = basalEliminationPerHour
            self.doseDecayPerGram = doseDecayPerGram
        }

        /// a1…a5 = 0.97, 0.22, 0.07, 0.03, 0.001 (2016b Table 2; 2016a Table 2; 2013 Eq 2).
        public static let publishedHarmonics: [Double] = [0.97, 0.22, 0.07, 0.03, 0.001]

        /// 2016b Table 3, "Lapse" column (10-min PVT lapses, RT > 500 ms).
        public static let lapses2016b = Parameters(
            upperAsymptote: 18.4, wakeTimeConstantHours: 40.0, sleepTimeConstantHours: 2.1,
            initialS: 0.5, circadianAmplitude: 3.3, circadianPhaseHours: 2.3,
            debtTimeConstantHours: 7.0 * 24, initialL: 0.0, debtFloor: -0.11,
            harmonics: publishedHarmonics, circadianPeriodHours: 24,
            amplitudeSlopePerGram: 9.86, basalEliminationPerHour: 0.49, doseDecayPerGram: 1.63)

        /// 2016b Table 3, "Mean RT" column (10-min PVT mean response time, ms).
        public static let meanRT2016b = Parameters(
            upperAsymptote: 497, wakeTimeConstantHours: 23.0, sleepTimeConstantHours: 4.0,
            initialS: 176, circadianAmplitude: 75, circadianPhaseHours: 2.5,
            debtTimeConstantHours: 7.0 * 24, initialL: 140, debtFloor: -0.11,
            harmonics: publishedHarmonics, circadianPeriodHours: 24,
            amplitudeSlopePerGram: 3.59, basalEliminationPerHour: 0.49, doseDecayPerGram: 1.63)
    }

    /// Caffeine formulations with a published absorption rate ka
    /// (2016b Table 3, from Kamimori et al. 2002, its ref 21).
    public enum Formulation: String, Codable, Sendable {
        case capsule, gum
        public var absorptionPerHour: Double {
            switch self {
            case .capsule: 2.06
            case .gum: 3.21
            }
        }
    }

    public enum State: String, Codable, Sendable { case awake, asleep }

    /// One contiguous episode. Episodes follow each other from t = 0.
    public struct Episode: Codable, Equatable, Sendable {
        public var state: State
        public var hours: Double
        public init(_ state: State, hours: Double) { self.state = state; self.hours = hours }
    }

    /// One dose: `grams` of caffeine at model time `atHours`.
    public struct Dose: Codable, Equatable, Sendable {
        public var atHours: Double
        public var grams: Double
        public var formulation: Formulation
        public init(atHours: Double, grams: Double, formulation: Formulation) {
            self.atHours = atHours; self.grams = grams; self.formulation = formulation
        }
    }

    public enum Refusal: Error, Equatable, Sendable {
        /// An episode has a non-positive or non-finite length.
        case invalidEpisode(index: Int)
        /// A requested time is outside [0, end of schedule].
        case timeOutsideSchedule(Double)
        /// Dose amount or time is negative, non-finite, or outside the schedule.
        case invalidDose
        /// FLAGGED F2: repeated doses are not implemented (not published for this gPD form).
        case repeatedDosesNotPublished
        /// τLA equals τs, or ka equals kc: the published closed forms divide by zero.
        case degenerateTimeConstants
    }

    public struct Sample: Equatable, Sendable {
        public var t: Double
        public var state: State
        /// Homeostatic process S (Eq 4 / ODE Eq 3 of 2016a).
        public var homeostatic: Double
        /// Lower asymptote L (Eq 5).
        public var lowerAsymptote: Double
        /// Circadian process C, before κ (Eq 3).
        public var circadian: Double
        /// P0 = S + κC (Eq 2).
        public var caffeineFree: Double
        /// gPD (Eq 6); 1 before the dose or with no dose.
        public var caffeineFactor: Double
        /// P = P0 × gPD (Eq 1).
        public var impairment: Double
    }

    // MARK: Components

    /// Process C, 2016b Table 2 Eq 3: Σ aᵢ sin(i·2π(t + φ)/τ). `t` in model hours.
    public static func circadian(atHours t: Double, _ p: Parameters) -> Double {
        var c = 0.0
        for (k, a) in p.harmonics.enumerated() {
            let i = Double(k + 1)
            c += a * sin(i * 2 * Double.pi * (t + p.circadianPhaseHours) / p.circadianPeriodHours)
        }
        return c
    }

    /// Caffeine-effect factor gPD, 2016b Table 2 Eq 6a–6b, for one dose of
    /// `grams` taken `hoursSinceDose` ago. Returns 1 before the dose
    /// (2014 Eq 6, "1 for t < t1").
    public static func caffeineFactor(hoursSinceDose dt: Double, grams c: Double, absorptionPerHour ka: Double, _ p: Parameters) throws -> Double {
        guard dt.isFinite, c.isFinite, c >= 0, ka.isFinite, ka > 0 else { throw Refusal.invalidDose }
        if dt < 0 || c == 0 { return 1 }
        let mc = p.amplitudeSlopePerGram * c
        let kc = p.basalEliminationPerHour * exp(-p.doseDecayPerGram * c)
        guard ka != kc else { throw Refusal.degenerateTimeConstants }
        let x = mc * ka / (ka - kc) * (exp(-kc * dt) - exp(-ka * dt))
        return 1 / (1 + x)
    }

    /// Advances (S, L) through `hours` of one state.
    ///
    /// Wake: S = U − (U − S0)e^(−t/τw); L = max(U − (U − L0)e^(−t/τLA), floor·U)
    /// (2016b Eqs 4–5). Sleep: dS/dt = (L − S)/τs with L from Eq 5 (2016a
    /// Table 2 Eq 3; Priezjev 2023 Table 2 Eq 4). Until L reaches the floor
    /// this is exactly 2016b Eq 4's closed form; after it, L is constant and
    /// S relaxes to it with τs. See FLAGGED F4 for why the ODE is followed.
    static func advance(s: Double, l: Double, hours t: Double, state: State, _ p: Parameters) throws -> (s: Double, l: Double) {
        let u = p.upperAsymptote
        let tw = p.wakeTimeConstantHours, ts = p.sleepTimeConstantHours, tla = p.debtTimeConstantHours
        let floorL = p.debtFloor.map { $0 * u }
        switch state {
        case .awake:
            let s1 = u - (u - s) * exp(-t / tw)
            var l1 = u - (u - l) * exp(-t / tla)
            if let f = floorL { l1 = max(l1, f) }
            return (s1, l1)
        case .asleep:
            guard tla != ts else { throw Refusal.degenerateTimeConstants }
            let a = 2 * u
            func closed(_ s0: Double, _ l0: Double, _ t: Double) -> (Double, Double) {
                let s1 = -a + (a + s0) * exp(-t / ts) + (a + l0) * (tla / (tla - ts)) * (exp(-t / tla) - exp(-t / ts))
                let l1 = -a + (a + l0) * exp(-t / tla)
                return (s1, l1)
            }
            guard let f = floorL else { return closed(s, l, t) }
            if l <= f {
                // Eq 5 pins L at the floor for the whole sleep episode.
                return (f + (s - f) * exp(-t / ts), f)
            }
            // Time at which −2U + (2U + L0)e^(−t/τLA) reaches the floor.
            let tStar = tla * log((a + l) / (a + f))
            if t <= tStar { return closed(s, l, t) }
            let (sStar, _) = closed(s, l, tStar)
            return (f + (sStar - f) * exp(-(t - tStar) / ts), f)
        }
    }

    // MARK: Simulation

    /// Evaluates the model at each time in `times` (model hours from t = 0)
    /// for a contiguous `schedule`, starting from the parameter set's S0 and
    /// L0 at t = 0, with at most one dose.
    public static func simulate(schedule: [Episode], dose: [Dose] = [], at times: [Double], _ p: Parameters = .lapses2016b) throws -> [Sample] {
        for (i, e) in schedule.enumerated() where !(e.hours.isFinite && e.hours > 0) {
            throw Refusal.invalidEpisode(index: i)
        }
        let end = schedule.reduce(0) { $0 + $1.hours }
        guard dose.count <= 1 else { throw Refusal.repeatedDosesNotPublished }
        if let d = dose.first {
            guard d.atHours.isFinite, d.grams.isFinite, d.grams >= 0, d.atHours >= 0, d.atHours <= end else { throw Refusal.invalidDose }
        }
        return try times.map { t in
            guard t.isFinite, t >= 0, t <= end else { throw Refusal.timeOutsideSchedule(t) }
            var s = p.initialS, l = p.initialL
            var start = 0.0
            var state = schedule.first?.state ?? .awake
            for e in schedule {
                state = e.state
                let span = min(e.hours, t - start)
                (s, l) = try advance(s: s, l: l, hours: span, state: e.state, p)
                start += e.hours
                if start >= t { break }
            }
            let c = circadian(atHours: t, p)
            let p0 = s + p.circadianAmplitude * c
            var g = 1.0
            if let d = dose.first {
                g = try caffeineFactor(hoursSinceDose: t - d.atHours, grams: d.grams, absorptionPerHour: d.formulation.absorptionPerHour, p)
            }
            return Sample(t: t, state: state, homeostatic: s, lowerAsymptote: l, circadian: c,
                          caffeineFree: p0, caffeineFactor: g, impairment: p0 * g)
        }
    }
}
#endif
