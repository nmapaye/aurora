import Foundation
import Testing
@testable import AuroraCore

@Suite struct AlertnessModelUpgradesTests {
    static let zones = ["UTC", "America/Los_Angeles"]
    // 2026-10-15 12:00:00 UTC baseline
    static let anchorDay: Millis = 1_792_065_600_000

    private func clock(_ id: String) -> LocalClock {
        LocalClock(timeZone: TimeZone(identifier: id)!)
    }

    private func sleepNight(
        id: String,
        dayOffset: Int,
        startHour: Double,
        durationHours: Double,
        baseDayStart: Millis,
        clock: LocalClock
    ) -> SleepSession {
        let dayStart = clock.addingDays(dayOffset, to: baseDayStart)
        let start = dayStart + startHour * hourMs
        return SleepSession(id: id, start: start, end: start + durationHours * hourMs)
    }

    // MARK: - 1. Sleep-Midpoint Circadian Anchor

    @Test(arguments: zones)
    func circadianAnchorRequiresMinimumNights(zone: String) {
        let c = clock(zone)
        let base = c.startOfDay(Self.anchorDay)
        let now = base + 14 * hourMs

        let fourNights = (-4 ... -1).map {
            sleepNight(id: "manual:sleep:\($0)", dayOffset: $0, startHour: 2, durationHours: 8, baseDayStart: base, clock: c)
        }
        let anchor4 = Circadian.anchor(sleeps: fourNights, at: now, clock: c)
        #expect(anchor4.source == .defaultFixed)
        #expect(anchor4.troughHour == Circadian.defaultTroughHour)
        #expect(anchor4.recordedNights == 4)
        #expect(!anchor4.includesSample)

        let fiveNights = (-5 ... -1).map {
            sleepNight(id: "manual:sleep:\($0)", dayOffset: $0, startHour: 2, durationHours: 8, baseDayStart: base, clock: c)
        }
        let anchor5 = Circadian.anchor(sleeps: fiveNights, at: now, clock: c)
        #expect(anchor5.source == .earlyRead)
        #expect(abs(anchor5.troughHour - 6.0) < 0.05)
        #expect(anchor5.recordedNights == 5)
    }

    @Test(arguments: zones)
    func circadianAnchorPersonalizesNightOwlsAndEarlyBirdsAndResistsOutliers(zone: String) {
        let c = clock(zone)
        let base = c.startOfDay(Self.anchorDay)
        let now = base + 14 * hourMs

        // Night owls sleeping 2 AM – 10 AM → midpoint 6:00 AM
        var owlSleeps = (-7 ... -1).map {
            sleepNight(id: "healthkit:sleep:sample:owl-\($0)", dayOffset: $0, startHour: 2, durationHours: 8, baseDayStart: base, clock: c)
        }
        // Single wild 8-hour shifted outlier night (should be ignored by circular median)
        owlSleeps.append(sleepNight(id: "healthkit:sleep:sample:outlier", dayOffset: -8, startHour: 14, durationHours: 8, baseDayStart: base, clock: c))

        let owlAnchor = Circadian.anchor(sleeps: owlSleeps, at: now, clock: c)
        #expect(owlAnchor.source == .personalized)
        #expect(owlAnchor.recordedNights == 8)
        #expect(abs(owlAnchor.troughHour - 6.0) < 0.05)

        // Early birds sleeping 9 PM – 5 AM (crossing midnight) → midpoint 1:00 AM
        let earlySleeps = (-7 ... -1).map {
            sleepNight(id: "manual:sleep:early-\($0)", dayOffset: $0, startHour: -3, durationHours: 8, baseDayStart: base, clock: c)
        }
        let earlyAnchor = Circadian.anchor(sleeps: earlySleeps, at: now, clock: c)
        #expect(earlyAnchor.source == .personalized)
        #expect(earlyAnchor.recordedNights == 7)
        #expect(abs(earlyAnchor.troughHour - 1.0) < 0.05)
    }

    @Test(arguments: zones)
    func circadianAnchorDetectsSampleDataAndEstimateRoundTrips(zone: String) throws {
        let c = clock(zone)
        let base = c.startOfDay(Self.anchorDay)
        let now = base + 14 * hourMs

        var sleeps = (-6 ... -1).map {
            sleepNight(id: "manual:sleep:n-\($0)", dayOffset: $0, startHour: 2, durationHours: 8, baseDayStart: base, clock: c)
        }
        sleeps.append(sleepNight(id: "demo:sleep:last", dayOffset: 0, startHour: 2, durationHours: 8, baseDayStart: base, clock: c))

        let inputs = EstimateInputs(
            halfLifeHours: 5,
            targetSleepHours: 8,
            clock: c,
            usePersonalCircadianPhase: true,
            useAbsorptionRamp: false
        )
        let estimate = EnergyEstimate.capture(at: now, doses: [], sleeps: sleeps, inputs: inputs)
        #expect(estimate.circadianAnchor?.source == .personalized)
        #expect(estimate.circadianAnchor?.includesSample == true)
        #expect(estimate.includesSample)

        let raw = Alertness.score(
            at: now,
            doses: [],
            sleeps: sleeps,
            halfLifeHours: 5,
            targetSleepHours: 8,
            clock: c,
            circadianTroughHour: estimate.circadianAnchor?.troughHour,
            useAbsorptionRamp: false
        )
        #expect(abs((estimate.unroundedScore ?? -1) - raw) < 1e-9)

        // Night owl at 2 PM is earlier in their cycle than a default 3 AM sleeper (peak shifted from 3 PM to 6 PM).
        let fixedInputs = EstimateInputs(halfLifeHours: 5, targetSleepHours: 8, clock: c)
        let fixedEstimate = EnergyEstimate.capture(at: now, doses: [], sleeps: sleeps, inputs: fixedInputs)
        #expect((estimate.unroundedScore ?? 0) < (fixedEstimate.unroundedScore ?? 0))

        // JSON Codable round-trip
        let data = try JSONEncoder().encode(estimate)
        let decoded = try JSONDecoder().decode(EnergyEstimate.self, from: data)
        #expect(decoded == estimate)

        // Explanation includes midpoint anchor and obeys CopyRules
        let explanation = AlertnessExplanation.explain(estimate, text: fixtureText)
        let timeFactor = explanation.factors.first { $0.kind == .timeOfDay }
        #expect(timeFactor?.detail.contains("6:00 AM") == true)
        #expect(timeFactor?.detail.contains("7 nights") == true)
        for line in explanation.allText {
            #expect(CopyRules.violations(in: line).isEmpty, "CopyRules violation: \(line)")
        }
    }

    @Test func formatClockHourHandlesMidnightAndAfternoon() {
        #expect(Circadian.Anchor.formatClockHour(0.0) == "12:00 AM")
        #expect(Circadian.Anchor.formatClockHour(3.75) == "3:45 AM")
        #expect(Circadian.Anchor.formatClockHour(12.5) == "12:30 PM")
        #expect(Circadian.Anchor.formatClockHour(23.5) == "11:30 PM")
        #expect(Circadian.Anchor.formatClockHour(24.0) == "12:00 AM")
    }

    // MARK: - 2. Gradual Caffeine Onset Ramp

    @Test func absorptionRampStartsAtZeroPeaksNear40MinAndConverges() {
        let mg = 100.0
        let halfLife = 5.0

        // Zero jump at t = 0
        #expect(Caffeine.singleDoseMg(mg: mg, elapsedMs: 0, halfLifeHours: halfLife, useAbsorptionRamp: true) == 0)

        // Peak occurs between 35 and 45 minutes
        let peakMinutes = Caffeine.peakAbsorptionMinutes(halfLifeHours: halfLife)
        #expect(peakMinutes >= 35 && peakMinutes <= 45)
        let atPeak = Caffeine.singleDoseMg(mg: mg, elapsedMs: peakMinutes * minuteMs, halfLifeHours: halfLife, useAbsorptionRamp: true)
        let beforePeak = Caffeine.singleDoseMg(mg: mg, elapsedMs: 20 * minuteMs, halfLifeHours: halfLife, useAbsorptionRamp: true)
        let afterPeak = Caffeine.singleDoseMg(mg: mg, elapsedMs: 60 * minuteMs, halfLifeHours: halfLife, useAbsorptionRamp: true)
        #expect(atPeak > beforePeak && atPeak > afterPeak)

        // Converges onto pure exponential half-life decay within 0.1% by 2h and 6h
        for hours in [2.0, 6.0] {
            let rampMg = Caffeine.singleDoseMg(mg: mg, elapsedMs: hours * hourMs, halfLifeHours: halfLife, useAbsorptionRamp: true)
            let expMg = Caffeine.singleDoseMg(mg: mg, elapsedMs: hours * hourMs, halfLifeHours: halfLife, useAbsorptionRamp: false)
            #expect(abs(rampMg - expMg) / expMg < 0.001)
        }

        // Extreme inputs stay finite and safe
        for bad in [
            Caffeine.singleDoseMg(mg: mg, elapsedMs: -1000, halfLifeHours: halfLife, useAbsorptionRamp: true),
            Caffeine.singleDoseMg(mg: mg, elapsedMs: 1e12, halfLifeHours: 0.01, useAbsorptionRamp: true),
            Caffeine.singleDoseMg(mg: .nan, elapsedMs: hourMs, halfLifeHours: halfLife, useAbsorptionRamp: true),
            Caffeine.singleDoseMg(mg: mg, elapsedMs: hourMs, halfLifeHours: 0, useAbsorptionRamp: true),
        ] {
            #expect(bad.isFinite && bad >= 0)
        }
    }

    @Test(arguments: zones)
    func absorptionRampIntegratesIntoEnergyEstimateAndExplanation(zone: String) {
        let c = clock(zone)
        let base = c.startOfDay(Self.anchorDay)
        let now = base + 9 * hourMs
        let sleep = sleepNight(id: "manual:sleep:1", dayOffset: 0, startHour: 0, durationHours: 7, baseDayStart: base, clock: c)
        let dose = Dose(id: "manual:dose:1", timestamp: now - 5 * minuteMs, mg: 200, source: "Espresso")

        let rampInputs = EstimateInputs(halfLifeHours: 5, targetSleepHours: 8, clock: c, useAbsorptionRamp: true)
        let expInputs = EstimateInputs(halfLifeHours: 5, targetSleepHours: 8, clock: c, useAbsorptionRamp: false)

        let rampEstimate = EnergyEstimate.capture(at: now, doses: [dose], sleeps: [sleep], inputs: rampInputs)
        let expEstimate = EnergyEstimate.capture(at: now, doses: [dose], sleeps: [sleep], inputs: expInputs)

        #expect(rampEstimate.usesAbsorptionRamp == true)
        #expect(expEstimate.usesAbsorptionRamp == nil)
        #expect(rampEstimate.evidence.activeCaffeineMg < expEstimate.evidence.activeCaffeineMg)

        let explanation = AlertnessExplanation.explain(rampEstimate, text: fixtureText)
        let cafFactor = explanation.factors.first { $0.kind == .caffeine }
        #expect(cafFactor?.detail.contains("onset ramp") == true)
        for line in explanation.allText {
            #expect(CopyRules.violations(in: line).isEmpty, "CopyRules violation: \(line)")
        }
    }

    // MARK: - 3. One-Tap Half-Life Calibration

    @Test(arguments: zones)
    func halfLifeCalibrationInsufficientDataAndSampleExclusion(zone: String) {
        let c = clock(zone)
        let base = c.startOfDay(Self.anchorDay)
        let now = base + 14 * hourMs

        var state = AppState()
        // 13 real KSS + 10 sample KSS should still report insufficientData(13, 14)
        for i in 0 ..< 13 {
            let day = c.addingDays(-i, to: base)
            state.sleeps.append(SleepSession(id: "manual:sleep:\(i)", start: day, end: day + 7 * hourMs))
            state.doses.append(Dose(id: "manual:dose:\(i)", timestamp: day + 8 * hourMs, mg: 150))
            state.energyCheckIns.append(EnergyCheckIn(id: "checkin:\(i)", recordedAt: day + 12 * hourMs, rating: 4, scale: .kss))
        }
        for i in 0 ..< 10 {
            let day = c.addingDays(-i, to: base)
            state.energyCheckIns.append(EnergyCheckIn(id: "demo:checkin:\(i)", recordedAt: day + 13 * hourMs, rating: 3, scale: .kss))
            // Also legacy energy5 check-ins should be ignored
            state.energyCheckIns.append(EnergyCheckIn(id: "legacy:\(i)", recordedAt: day + 13 * hourMs, rating: 3, scale: .energy5))
        }

        let status = HalfLifeCalibration.evaluate(state: state, now: now, clock: c)
        #expect(status == .insufficientData(pairedCount: 13, needed: 14))
    }

    @Test(arguments: zones)
    func halfLifeCalibrationRecoversSlowMetabolizerDespiteBias(zone: String) {
        let c = clock(zone)
        let base = c.startOfDay(Self.anchorDay)
        let now = base + 20 * hourMs

        var state = AppState()
        state.prefs.halfLife = 5.0
        state.prefs.targetSleep = 8.0

        // Generate 16 paired logs across 16 days for a true 7.5 h metabolizer with varied caffeine timing
        // and moderate sleep debt so synthetic true scores stay in ~35–75, then add +18 constant user bias.
        let trueHalfLife = 7.5
        let bias = 18.0
        let delaysHours = [1.0, 4.0, 8.0, 12.0, 15.0, 2.0, 6.0, 10.0, 14.0, 16.0, 3.0, 7.0, 11.0, 13.0, 9.0, 5.0]

        for i in 0 ..< 16 {
            let dayOffset = -(i + 1)
            let day = c.addingDays(dayOffset, to: base)
            // 6h sleep (01:00 to 07:00) keeps scores in mid-band with zero clipping even after +18 bias
            let sleep = SleepSession(id: "manual:sleep:\(i)", start: day + 1 * hourMs, end: day + 7 * hourMs)
            state.sleeps.append(sleep)

            let doseHour = i.isMultiple(of: 2) ? 7.5 : 8.0
            let doseTime = day + doseHour * hourMs
            let doseMg = i.isMultiple(of: 3) ? 240.0 : 180.0
            let dose = Dose(id: "manual:dose:\(i)", timestamp: doseTime, mg: doseMg)
            state.doses.append(dose)

            let obsTime = doseTime + delaysHours[i] * hourMs
            let trueScore = Alertness.score(
                at: obsTime,
                doses: state.doses,
                sleeps: state.sleeps,
                halfLifeHours: trueHalfLife,
                targetSleepHours: state.prefs.targetSleep,
                clock: c
            )
            let biased = min(98.0, max(5.0, trueScore + bias))

            if i < 6 {
                // Mix in KSS check-ins
                let kss = Int(clamp(jsRound(9.0 - biased / 100.0 * 8.0), 1, 9))
                state.energyCheckIns.append(EnergyCheckIn(id: "checkin:\(i)", recordedAt: obsTime, rating: kss, scale: .kss))
            } else {
                // Mix in protocol-2 Reaction Tests
                let rtScore = Int(clamp(jsRound(biased), 0, 100))
                let session = VigilanceSession(
                    id: "vigilance:\(i)",
                    startedAt: obsTime - 30_000,
                    completedAt: obsTime,
                    durationMs: 30_000,
                    trialCount: 8,
                    validReactionCount: 8,
                    falseStartCount: 0,
                    lapseCount: 0,
                    medianReactionMs: 260,
                    meanReactionMs: 260,
                    fastestReactionMs: 220,
                    reactionStdDevMs: 20,
                    score: rtScore,
                    rating: .steady,
                    protocolVersion: 2
                )
                state.vigilanceSessions.append(session)
            }
        }

        let before = state
        let status = HalfLifeCalibration.evaluate(state: state, now: now, clock: c)
        #expect(state == before) // evaluate never mutates state

        guard case .proposed(let proposal) = status else {
            Issue.record("Expected proposal for 7.5h slow metabolizer, got \(status)")
            return
        }
        #expect(proposal.currentHalfLifeHours == 5.0)
        #expect(proposal.proposedHalfLifeHours >= 6.5)
        #expect(proposal.pairedObservations == 16)
        #expect(proposal.checkInCount == 6)
        #expect(proposal.reactionTestCount == 10)
        #expect(proposal.proposedError < proposal.currentError * 0.9)
        #expect(CopyRules.violations(in: proposal.reason).isEmpty, "Reason broke CopyRules: \(proposal.reason)")

        // Once user applies the proposed setting, re-evaluating reports aligned
        state.prefs.halfLife = proposal.proposedHalfLifeHours
        let afterApply = HalfLifeCalibration.evaluate(state: state, now: now, clock: c)
        guard case .aligned(let alignedHours, let count) = afterApply else {
            Issue.record("Expected aligned after applying proposal, got \(afterApply)")
            return
        }
        #expect(alignedHours == proposal.proposedHalfLifeHours)
        #expect(count == 16)
    }

    // MARK: - 4. Prefs Codable Backward Compatibility

    @Test func prefsUpgradesRoundTripAndOmitNilFromDefaults() throws {
        let defaultJSON = String(decoding: try JSONEncoder().encode(Prefs.defaults), as: UTF8.self)
        #expect(!defaultJSON.contains("personalCircadianPhase"))
        #expect(!defaultJSON.contains("gradualCaffeineOnset"))

        var custom = Prefs.defaults
        custom.personalCircadianPhase = true
        custom.gradualCaffeineOnset = true
        let encoded = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(Prefs.self, from: encoded)
        #expect(decoded == custom)
        #expect(decoded.usesPersonalCircadianPhase && decoded.usesGradualCaffeineOnset)
    }
}
