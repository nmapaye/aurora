#if AURORA_RESEARCH_CAFFEINE
import Foundation
import Testing
@testable import AuroraCore

/// Research-only UMP + caffeine model. Built in Debug only
/// (AURORA_RESEARCH_CAFFEINE in Package.swift), so plain `swift test` runs it.
///
/// Three kinds of test, kept apart on purpose:
/// 1. Transcription: every constant equals the value printed in the paper.
/// 2. Published-number checks: the few numbers the papers state in text,
///    each with its tolerance reason. Curves in the papers are figures only;
///    none is digitized here.
/// 3. Internal consistency: closed forms against an independent RK4
///    integration of the published differential equations. These verify the
///    code, not the science.
/// 4. Repeated doses (2014 Eqs 6–8): hand-worked recursion and structural
///    properties. No published repeated-dose curve is printed as numbers.
@Suite struct UMPCaffeineModelTests {
    typealias M = UMPCaffeineModel

    // MARK: 1. Transcription (exact)

    @Test func lapseParametersMatch2016bTable3() {
        let p = M.Parameters.lapses2016b
        #expect(p.upperAsymptote == 18.4)
        #expect(p.wakeTimeConstantHours == 40.0)
        #expect(p.sleepTimeConstantHours == 2.1)
        #expect(p.initialS == 0.5)
        #expect(p.circadianAmplitude == 3.3)
        #expect(p.circadianPhaseHours == 2.3)
        #expect(p.debtTimeConstantHours == 168) // 7.0 d
        #expect(p.initialL == 0.0)
        #expect(p.amplitudeSlopePerGram == 9.86)
        #expect(p.basalEliminationPerHour == 0.49)
        #expect(p.doseDecayPerGram == 1.63)
        #expect(p.debtFloor == -0.11)
        #expect(p.harmonics == [0.97, 0.22, 0.07, 0.03, 0.001])
        #expect(p.circadianPeriodHours == 24)
        #expect(M.Formulation.capsule.absorptionPerHour == 2.06)
        #expect(M.Formulation.gum.absorptionPerHour == 3.21)
    }

    @Test func meanRTParametersMatch2016bTable3() {
        let p = M.Parameters.meanRT2016b
        #expect(p.upperAsymptote == 497)
        #expect(p.wakeTimeConstantHours == 23.0)
        #expect(p.sleepTimeConstantHours == 4.0)
        #expect(p.initialS == 176)
        #expect(p.circadianAmplitude == 75)
        #expect(p.circadianPhaseHours == 2.5)
        #expect(p.debtTimeConstantHours == 168)
        #expect(p.initialL == 140)
        #expect(p.amplitudeSlopePerGram == 3.59)
        #expect(p.basalEliminationPerHour == 0.49)
        #expect(p.doseDecayPerGram == 1.63)
    }

    // MARK: 2. Published-number checks

    /// A debt-only parameter set: U = 1 so L equals Debt (2016a Eq 4,
    /// L = U × Debt). Other values do not affect L.
    static func debtOnly(tauLA: Double, floor: Double?) -> M.Parameters {
        var p = M.Parameters.lapses2016b
        p.upperAsymptote = 1; p.initialL = 0; p.initialS = 0
        p.debtTimeConstantHours = tauLA; p.debtFloor = floor
        return p
    }

    /// Debt over one 24 h wake-then-sleep cycle after `days` identical days,
    /// sampled every `step` hours.
    static func lastCycle(sleepHours: Double, tauLA: Double, days: Int = 120, step: Double = 0.01) throws -> [Double] {
        let p = debtOnly(tauLA: tauLA, floor: nil)
        var schedule: [M.Episode] = []
        for _ in 0..<days { schedule += [M.Episode(.awake, hours: 24 - sleepHours), M.Episode(.asleep, hours: sleepHours)] }
        let start = Double(days - 1) * 24
        let n = Int((24 / step).rounded())
        let times = (0...n).map { start + Double($0) * step }
        return try M.simulate(schedule: schedule, at: times, p).map(\.lowerAsymptote)
    }

    static func trapezoidMean(_ y: [Double]) -> Double {
        var s = 0.0
        for i in 1..<y.count { s += (y[i - 1] + y[i]) / 2 }
        return s / Double(y.count - 1)
    }

    /// 2016a p. 250: the −0.11 debt floor "corresponds to the asymptotic debt
    /// limit associated with 8.9 h of sleep/day". For the linear debt filter
    /// (Eq 5a) the cycle-mean debt equals the cycle-mean Loss:
    /// (15.1·1 + 8.9·(−2))/24 = −0.1125. Tolerance 0.005: the paper rounds
    /// to two decimals. Quadrature error (step 0.01 h) is < 1e-5.
    @Test func debtFloorMatches8point9HoursOfSleep() throws {
        let mean = Self.trapezoidMean(try Self.lastCycle(sleepHours: 8.9, tauLA: 168))
        #expect(abs(mean - (-0.1125)) < 1e-5)
        #expect(abs(mean - (-0.11)) <= 0.005)
    }

    /// Rajdev 2013 §2.3: 3-h TIB gives an AUC for Loss of 0.625 per day and
    /// Debt approaches a limit cycle around 0.625. Exact arithmetic; the
    /// tolerance 1e-5 covers trapezoid quadrature only.
    @Test func threeHourTIBLimitCycleCentresOn0point625() throws {
        let mean = Self.trapezoidMean(try Self.lastCycle(sleepHours: 3, tauLA: 120))
        #expect(abs(mean - 0.625) < 1e-5)
    }

    /// Rajdev 2013 §2.3: with 8-h TIB, L "would oscillate around zero" and
    /// with τLA = 120 h "the magnitude of this oscillation would be 0.06 U".
    /// The paper gives one significant figure and does not say whether
    /// magnitude means half or full peak-to-peak. Half peak-to-peak computes
    /// to ≈ 0.066; tolerance 0.01 reflects the one-figure reporting. This is a
    /// consistency check, not a precise parity value.
    @Test func eightHourTIBOscillatesAroundZeroWithMagnitudeNear0point06() throws {
        let cycle = try Self.lastCycle(sleepHours: 8, tauLA: 120)
        #expect(abs(Self.trapezoidMean(cycle)) < 1e-5)
        let half = (cycle.max()! - cycle.min()!) / 2
        #expect(abs(half - 0.06) <= 0.01)
    }

    /// Rajdev 2013 §3.2: under TSD, L reaches 1 − 1/e ≅ 63.2% of its final
    /// value in τLA and 95% in 3τLA. Tolerance 5e-4: the paper rounds to
    /// 0.1% (63.2%) and whole percent (95%; exact 1 − e⁻³ = 95.02%).
    @Test func tsdDebtTimeConstantMilestones() throws {
        let tau = 4.06 * 24 // Rajdev 2013 Table 1 unified-model τLA
        let p = Self.debtOnly(tauLA: tau, floor: nil)
        let s = try M.simulate(schedule: [M.Episode(.awake, hours: 3 * tau)], at: [tau, 3 * tau], p)
        #expect(abs(s[0].lowerAsymptote - 0.632) < 5e-4)
        #expect(abs(s[1].lowerAsymptote - 0.95) < 1e-3)
    }

    /// 2016a p. 250 / 2013 §2.3: debt is bounded by 1 (total sleep loss) and
    /// −2 (24 h sleep/day) without the floor, and by −0.11 with it.
    @Test func debtLimits() throws {
        let long = 40 * 168.0
        let noFloor = Self.debtOnly(tauLA: 168, floor: nil)
        let up = try M.simulate(schedule: [M.Episode(.awake, hours: long)], at: [long], noFloor)[0].lowerAsymptote
        let down = try M.simulate(schedule: [M.Episode(.asleep, hours: long)], at: [long], noFloor)[0].lowerAsymptote
        #expect(abs(up - 1) < 1e-9)
        #expect(abs(down - (-2)) < 1e-9)
        let floored = Self.debtOnly(tauLA: 168, floor: -0.11)
        let f = try M.simulate(schedule: [M.Episode(.asleep, hours: long)], at: [long], floored)[0].lowerAsymptote
        #expect(f == -0.11)
    }

    /// 2016b p. 1831: "P0(t) is equivalent to Pc(t) for c = 0 mg", and
    /// gPD is 1 before the dose (2014 Eq 6). Exact.
    @Test func noCaffeineMeansNoEffect() throws {
        let sched = [M.Episode(.awake, hours: 16), M.Episode(.asleep, hours: 8), M.Episode(.awake, hours: 16)]
        let times = stride(from: 0.0, through: 40, by: 0.5).map { $0 }
        let zero = try M.simulate(schedule: sched, dose: [M.Dose(atHours: 20, grams: 0, formulation: .capsule)], at: times)
        let none = try M.simulate(schedule: sched, at: times)
        #expect(zero == none)
        for s in none { #expect(s.caffeineFactor == 1 && s.impairment == s.caffeineFree) }
        let before = try M.simulate(schedule: sched, dose: [M.Dose(atHours: 20, grams: 0.2, formulation: .gum)], at: [19.99])
        #expect(before[0].caffeineFactor == 1)
    }

    /// 2016b p. 1829: 0 ≤ gPD ≤ 1, with gPD = 1 at the moment of intake for
    /// the absorption form (e^0 − e^0 = 0). Doses 0–1 g, 0–72 h after.
    @Test func caffeineFactorStaysInUnitInterval() throws {
        let p = M.Parameters.lapses2016b
        for mg in stride(from: 0.0, through: 1000, by: 25) {
            for f in [M.Formulation.capsule, .gum] {
                #expect(try M.caffeineFactor(hoursSinceDose: 0, grams: mg / 1000, absorptionPerHour: f.absorptionPerHour, p) == 1)
                for dt in stride(from: 0.0, through: 72, by: 0.25) {
                    let g = try M.caffeineFactor(hoursSinceDose: dt, grams: mg / 1000, absorptionPerHour: f.absorptionPerHour, p)
                    #expect(g > 0 && g <= 1)
                }
            }
        }
    }

    // MARK: 3. Internal consistency (code, not science)

    /// Independent fixed-step RK4 of the published ODEs: 2016a Table 2 Eq 3
    /// (S), Eq 5a–5b (Debt), L = U·Debt with the 2016b Eq 5 floor applied as
    /// a clamp after each step.
    static func rk4(_ p: M.Parameters, schedule: [M.Episode], until t: Double, h: Double) -> (Double, Double) {
        let u = p.upperAsymptote
        var s = p.initialS, l = p.initialL, now = 0.0
        let floorL = p.debtFloor.map { $0 * u }
        if let f = floorL { l = max(l, f) }
        var idx = 0, segEnd = schedule[0].hours
        while now < t - 1e-12 {
            while now >= segEnd - 1e-12 && idx + 1 < schedule.count { idx += 1; segEnd += schedule[idx].hours }
            let dt = min(h, t - now, segEnd - now)
            let awake = schedule[idx].state == .awake
            func f(_ s: Double, _ l: Double) -> (Double, Double) {
                let ll = floorL.map { max(l, $0) } ?? l
                return awake ? ((u - s) / p.wakeTimeConstantHours, (u - ll) / p.debtTimeConstantHours)
                             : ((ll - s) / p.sleepTimeConstantHours, floorL != nil && ll <= floorL! ? 0 : (-2 * u - ll) / p.debtTimeConstantHours)
            }
            let k1 = f(s, l)
            let k2 = f(s + dt / 2 * k1.0, l + dt / 2 * k1.1)
            let k3 = f(s + dt / 2 * k2.0, l + dt / 2 * k2.1)
            let k4 = f(s + dt * k3.0, l + dt * k3.1)
            s += dt / 6 * (k1.0 + 2 * k2.0 + 2 * k3.0 + k4.0)
            l += dt / 6 * (k1.1 + 2 * k2.1 + 2 * k3.1 + k4.1)
            if let fl = floorL { l = max(l, fl) }
            now += dt
        }
        return (s, l)
    }

    static let restriction: [M.Episode] = (0..<7).flatMap { _ in [M.Episode(.awake, hours: 19), M.Episode(.asleep, hours: 5)] }
        + [M.Episode(.awake, hours: 40)]
        + (0..<3).flatMap { _ in [M.Episode(.asleep, hours: 10), M.Episode(.awake, hours: 14)] }

    /// Without the floor the closed forms are exact solutions of the ODE.
    /// Tolerance 1e-9: RK4 at h = 0.01 h has error ~1e-12 here.
    @Test func closedFormMatchesRK4WithoutFloor() throws {
        var p = M.Parameters.lapses2016b; p.debtFloor = nil
        for t in stride(from: 0.0, through: 240, by: 7.3) {
            let a = try M.simulate(schedule: Self.restriction, at: [t], p)[0]
            let (s, l) = Self.rk4(p, schedule: Self.restriction, until: t, h: 0.01)
            #expect(abs(a.homeostatic - s) < 1e-9)
            #expect(abs(a.lowerAsymptote - l) < 1e-9)
        }
    }

    /// With the floor, the clamp makes the ODE right-hand side non-smooth,
    /// so fixed-step RK4 is only first-order accurate at the crossing.
    /// Tolerance 1e-5 lapses at h = 0.001 h.
    @Test func floorHandlingMatchesRK4() throws {
        let p = M.Parameters.lapses2016b
        let long: [M.Episode] = [M.Episode(.asleep, hours: 14), M.Episode(.awake, hours: 10), M.Episode(.asleep, hours: 14)]
        for t in stride(from: 0.0, through: 38, by: 1.7) {
            let a = try M.simulate(schedule: long, at: [t], p)[0]
            let (s, l) = Self.rk4(p, schedule: long, until: t, h: 0.001)
            #expect(abs(a.homeostatic - s) < 1e-5)
            #expect(abs(a.lowerAsymptote - l) < 1e-5)
        }
    }

    @Test func circadianIsPeriodicAndUsesPublishedForm() {
        let p = M.Parameters.lapses2016b
        for t in stride(from: 0.0, through: 24, by: 0.5) {
            #expect(abs(M.circadian(atHours: t, p) - M.circadian(atHours: t + 24, p)) < 1e-12)
            var expected = 0.0
            for (k, a) in [0.97, 0.22, 0.07, 0.03, 0.001].enumerated() {
                expected += a * sin(Double(k + 1) * 2 * .pi * (t + 2.3) / 24)
            }
            #expect(M.circadian(atHours: t, p) == expected)
        }
    }

    // MARK: 4. Repeated doses (2014 Eqs 6–8, no absorption)

    /// 2014 Table 1, study A (p. 15): M0 = 9.86 g⁻¹, k0 = 0.49 h⁻¹,
    /// z = 1.63 g⁻¹, fitted with the repeated-dose model on all three
    /// post-dose blocks. 2016b Table 3's lapse values are the same numbers.
    /// Exact.
    @Test func lapseCaffeineConstantsEqual2014Table1StudyA() {
        let p = M.Parameters.lapses2016b
        #expect(p.amplitudeSlopePerGram == 9.86)
        #expect(p.basalEliminationPerHour == 0.49)
        #expect(p.doseDecayPerGram == 1.63)
        #expect(M.Formulation.instantaneous.absorptionPerHour == .infinity)
    }

    /// Vital-Lopez et al. 2024 (Sleep 47:zsae133, p. 4): after a dose gPD
    /// reaches "a minimum after about 45 minutes" and then reaches "0.95 in
    /// about 7.4 hours for a 100-mg dose and 13.7 hours for a 300-mg dose".
    /// The paper does not say which parameter set or formulation; of the
    /// four published combinations only the lapse set with gum (ka 3.21)
    /// gives all three numbers at the printed precision (capsule gives 7.6 h
    /// and 13.9 h), so that is an inference. Tolerances: minimum 42–48 min
    /// ("about"), 0.95 times within 0.05 h (printed to 0.1 h).
    /// Single dose, absorption form; grid 0.001 h.
    @Test func singleDoseTimingsMatchVitalLopez2024() throws {
        let p = M.Parameters.lapses2016b
        func profile(_ grams: Double) throws -> (tMin: Double, t95: Double) {
            let ts = (1...30000).map { Double($0) / 1000 }
            let g = try ts.map { try M.caffeineFactor(hoursSinceDose: $0, grams: grams, absorptionPerHour: M.Formulation.gum.absorptionPerHour, p) }
            let iMin = g.indices.min { g[$0] < g[$1] }!
            let i95 = g.indices.first { $0 > iMin && g[$0] >= 0.95 }!
            return (ts[iMin], ts[i95])
        }
        let d100 = try profile(0.1), d300 = try profile(0.3)
        #expect(d100.tMin * 60 >= 42 && d100.tMin * 60 <= 48)
        #expect(abs(d100.t95 - 7.4) < 0.05)
        #expect(abs(d300.t95 - 13.7) < 0.05)
    }

    static func eq3(_ dt: Double, _ c: Double, _ p: M.Parameters) -> Double {
        dt < 0 ? 1 : 1 / (1 + p.amplitudeSlopePerGram * c * exp(-p.basalEliminationPerHour * exp(-p.doseDecayPerGram * c) * dt))
    }

    /// 2014 p. 14: "The repeated-dose model in Eq. (6) reduces to Eq. (3)
    /// under single-dose conditions." Exact to rounding (1e-15).
    @Test func oneInstantaneousDoseIsEq3() throws {
        let p = M.Parameters.lapses2016b
        for c in [0.05, 0.1, 0.2, 0.6] {
            let d = [M.Dose(atHours: 10, grams: c, formulation: .instantaneous)]
            for t in stride(from: 0.0, through: 60, by: 0.25) {
                let r = try M.repeatedDoseFactor(atHours: t, doses: d, p)
                let single = try M.caffeineFactor(hoursSinceDose: t - 10, grams: c, absorptionPerHour: .infinity, p)
                #expect(abs(r - Self.eq3(t - 10, c, p)) < 1e-15)
                #expect(abs(single - Self.eq3(t - 10, c, p)) < 1e-15)
            }
        }
    }

    /// 2014 Eq 3 is the ka → ∞ limit of 2016b Eq 6a for t > t0. Code check:
    /// ka = 1e7 h⁻¹ against `.infinity`, 0.1–48 h after a dose, within 1e-6.
    @Test func eq3IsLargeKaLimitOfEq6a() throws {
        let p = M.Parameters.lapses2016b
        for c in [0.1, 0.4] {
            for dt in stride(from: 0.1, through: 48, by: 0.1) {
                let a = try M.caffeineFactor(hoursSinceDose: dt, grams: c, absorptionPerHour: 1e7, p)
                let b = try M.caffeineFactor(hoursSinceDose: dt, grams: c, absorptionPerHour: .infinity, p)
                #expect(abs(a - b) < 1e-6)
            }
        }
    }

    /// 2014 Eqs 6–8 worked by hand for the 2014 study design (three 200-mg
    /// doses at 20, 22 and 24 h of sleep loss, 2014 Table 2 caption), with
    /// E(t2⁻) = 0.2·e^(−k(0.2)·2) and E(t3⁻) = [E(t2⁻) + 0.2]·e^(−k(t2)·2).
    /// Transcription check of the recursion, not a published curve: the
    /// paper shows these curves only as Fig. C.1. Tolerance 1e-12.
    @Test func threeDosesMatchHandWorkedEqs6to8() throws {
        let p = M.Parameters.lapses2016b
        let m0 = 9.86, k0 = 0.49, z = 1.63
        func k(_ g: Double) -> Double { k0 * exp(-z * g) }
        let e2 = 0.2 * exp(-k(0.2) * 2)
        let e3 = (e2 + 0.2) * exp(-k(0.2 + e2) * 2)
        func expected(_ t: Double) -> Double {
            if t < 20 { return 1 }
            if t < 22 { return 1 / (1 + m0 * 0.2 * exp(-k(0.2) * (t - 20))) }
            if t < 24 { return 1 / (1 + m0 * (0.2 + e2) * exp(-k(0.2 + e2) * (t - 22))) }
            return 1 / (1 + m0 * (0.2 + e3) * exp(-k(0.2 + e3) * (t - 24)))
        }
        let doses = [20.0, 22, 24].map { M.Dose(atHours: $0, grams: 0.2, formulation: .instantaneous) }
        for t in [0, 19.99, 20, 21, 21.999, 22, 23, 23.999, 24, 26, 30, 48] {
            #expect(abs(try M.repeatedDoseFactor(atHours: t, doses: doses, p) - expected(t)) < 1e-12)
        }
        let s = M.extantState(atHours: 30, sortedDoses: doses, p)!
        #expect(abs(s.extantBeforeLast - e3) < 1e-15)
        #expect(abs(s.equivalentGrams - (0.2 + e3)) < 1e-15)
    }

    /// Consequence of reading Eq 8's rate as k_D(j−1) (FLAGGED F10): just
    /// before dose j, gPD equals [1 + M0·E(tj⁻)]⁻¹, i.e. the extant dose is
    /// exactly the caffeine Eq 6 still shows as active. Tolerance 1e-9 at
    /// 1e-9 h before the dose.
    @Test func gPDIsContinuousFromTheLeftAtEachDose() throws {
        let p = M.Parameters.lapses2016b
        let doses = [(3.0, 0.1), (5.5, 0.3), (6.0, 0.05), (14.0, 0.2)].map { M.Dose(atHours: $0.0, grams: $0.1, formulation: .instantaneous) }
        for (j, d) in doses.enumerated() where j > 0 {
            let before = try M.repeatedDoseFactor(atHours: d.atHours - 1e-9, doses: doses, p)
            let e = M.extantState(atHours: d.atHours, sortedDoses: doses, p)!.extantBeforeLast
            #expect(abs(before - 1 / (1 + p.amplitudeSlopePerGram * e)) < 1e-9)
        }
    }

    /// Doses far apart: the extant dose decays to nothing, so the later dose
    /// acts as a fresh single dose (Eq 8 with tj − tj−1 → ∞). 200 h apart
    /// E < 1e-20 g; tolerance 1e-12.
    @Test func farApartDosesActAsSingleDoses() throws {
        let p = M.Parameters.lapses2016b
        let doses = [M.Dose(atHours: 0, grams: 0.1, formulation: .instantaneous), M.Dose(atHours: 200, grams: 0.3, formulation: .instantaneous)]
        #expect(M.extantState(atHours: 200, sortedDoses: doses, p)!.extantBeforeLast < 1e-20)
        for dt in stride(from: 0.0, through: 40, by: 0.5) {
            #expect(abs(try M.repeatedDoseFactor(atHours: 200 + dt, doses: doses, p) - Self.eq3(dt, 0.3, p)) < 1e-12)
            #expect(abs(try M.repeatedDoseFactor(atHours: dt, doses: doses, p) - Self.eq3(dt, 0.1, p)) < 1e-12)
        }
    }

    /// Input order does not matter (doses are taken in time order), and two
    /// doses at the same moment equal one dose of their sum (Eq 8 with
    /// tj = tj−1 gives E = E + D). Tolerance 1e-15.
    @Test func doseOrderAndSameTimeSplitInvariance() throws {
        let p = M.Parameters.lapses2016b
        let a = [M.Dose(atHours: 2, grams: 0.1, formulation: .instantaneous), M.Dose(atHours: 6, grams: 0.2, formulation: .instantaneous), M.Dose(atHours: 9, grams: 0.15, formulation: .instantaneous)]
        let shuffled = [a[2], a[0], a[1]]
        let split = [M.Dose(atHours: 4, grams: 0.1, formulation: .instantaneous), M.Dose(atHours: 4, grams: 0.1, formulation: .instantaneous)]
        let whole = [M.Dose(atHours: 4, grams: 0.2, formulation: .instantaneous)]
        for t in stride(from: 0.0, through: 30, by: 0.25) {
            #expect(try M.repeatedDoseFactor(atHours: t, doses: a, p) == M.repeatedDoseFactor(atHours: t, doses: shuffled, p))
            #expect(abs(try M.repeatedDoseFactor(atHours: t, doses: split, p) - M.repeatedDoseFactor(atHours: t, doses: whole, p)) < 1e-15)
        }
    }

    /// 2014 p. 13: elimination slows "with cumulative increases in caffeine
    /// concentration from repeated doses". With caffeine still present, the
    /// second dose's rate is below that of the same dose taken alone and its
    /// effect is larger (lower gPD) at every time after it. Strict inequality.
    @Test func extantCaffeineSlowsEliminationAndDeepensEffect() throws {
        let p = M.Parameters.lapses2016b
        let doses = [M.Dose(atHours: 0, grams: 0.2, formulation: .instantaneous), M.Dose(atHours: 3, grams: 0.2, formulation: .instantaneous)]
        let s = M.extantState(atHours: 3, sortedDoses: doses, p)!
        #expect(s.extantBeforeLast > 0)
        #expect(s.rate < 0.49 * exp(-1.63 * 0.2))
        for dt in stride(from: 0.0, through: 24, by: 0.5) {
            #expect(try M.repeatedDoseFactor(atHours: 3 + dt, doses: doses, p) < Self.eq3(dt, 0.2, p))
        }
    }

    /// 0 < gPD ≤ 1 (2016b p. 1829) for repeated doses, and simulate applies
    /// P = P0 × gPD with the repeated-dose factor. Exact.
    @Test func repeatedDosesInSimulation() throws {
        let sched = [M.Episode(.awake, hours: 16), M.Episode(.asleep, hours: 8), M.Episode(.awake, hours: 40)]
        let doses = [20.0, 22, 24, 40, 41].map { M.Dose(atHours: $0, grams: 0.2, formulation: .instantaneous) }
        let times = stride(from: 0.0, through: 64, by: 0.25).map { $0 }
        let out = try M.simulate(schedule: sched, dose: doses, at: times)
        let base = try M.simulate(schedule: sched, at: times)
        for (s, b) in zip(out, base) {
            let g = try M.repeatedDoseFactor(atHours: s.t, doses: doses, .lapses2016b)
            #expect(s.caffeineFactor == g && g > 0 && g <= 1)
            #expect(s.caffeineFree == b.caffeineFree && s.impairment == b.caffeineFree * g)
            if s.t < 20 { #expect(g == 1) }
        }
    }

    /// One instantaneous dose through simulate equals 2014 Eq 3.
    @Test func singleInstantaneousDoseInSimulation() throws {
        let sched = [M.Episode(.awake, hours: 30)]
        let out = try M.simulate(schedule: sched, dose: [M.Dose(atHours: 20, grams: 0.2, formulation: .instantaneous)], at: [19, 20, 25])
        for s in out { #expect(abs(s.caffeineFactor - Self.eq3(s.t - 20, 0.2, .lapses2016b)) < 1e-15) }
    }

    // MARK: Refusals (flagged paths)

    @Test func refusesRepeatedDoses() {
        let d = M.Dose(atHours: 1, grams: 0.1, formulation: .gum)
        #expect(throws: M.Refusal.repeatedDosesNotPublished) {
            try M.simulate(schedule: [M.Episode(.awake, hours: 10)], dose: [d, d], at: [5])
        }
    }

    /// FLAGGED F2: repeated doses with absorption (capsule, gum) and mixed
    /// formulations stay refused; a zero-gram entry is not a dose.
    @Test func refusesRepeatedAbsorptionAndMixedDoses() throws {
        let sched = [M.Episode(.awake, hours: 10)]
        let cap = M.Dose(atHours: 1, grams: 0.1, formulation: .capsule)
        let inst = M.Dose(atHours: 2, grams: 0.1, formulation: .instantaneous)
        #expect(throws: M.Refusal.repeatedDosesNotPublished) { try M.simulate(schedule: sched, dose: [cap, cap], at: [5]) }
        #expect(throws: M.Refusal.repeatedDosesNotPublished) { try M.simulate(schedule: sched, dose: [cap, inst], at: [5]) }
        #expect(throws: M.Refusal.repeatedDosesNotPublished) { try M.repeatedDoseFactor(atHours: 5, doses: [cap], .lapses2016b) }
        let zero = M.Dose(atHours: 3, grams: 0, formulation: .capsule)
        let a = try M.simulate(schedule: sched, dose: [cap, zero], at: [5])
        let b = try M.simulate(schedule: sched, dose: [cap], at: [5])
        #expect(a == b)
        #expect(throws: M.Refusal.invalidDose) {
            try M.simulate(schedule: sched, dose: [inst, M.Dose(atHours: 11, grams: 0.1, formulation: .instantaneous)], at: [5])
        }
    }

    @Test func refusesBadInputs() {
        #expect(throws: M.Refusal.invalidEpisode(index: 0)) { try M.simulate(schedule: [M.Episode(.awake, hours: 0)], at: [0]) }
        #expect(throws: M.Refusal.timeOutsideSchedule(11)) { try M.simulate(schedule: [M.Episode(.awake, hours: 10)], at: [11]) }
        #expect(throws: M.Refusal.invalidDose) {
            try M.simulate(schedule: [M.Episode(.awake, hours: 10)], dose: [M.Dose(atHours: 2, grams: -0.1, formulation: .capsule)], at: [5])
        }
    }
}
#endif
