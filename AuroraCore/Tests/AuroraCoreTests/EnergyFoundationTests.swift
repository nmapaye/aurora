import Foundation
import Testing
@testable import AuroraCore

private let utc = LocalClock(timeZone: TimeZone(identifier: "UTC")!)
private let pacific = LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
private let now: Millis = 1_790_527_260_000 // 2026-09-27 16:41 UTC
/// 2026-11-01 08:00 UTC: 1:00 AM PDT, an hour before Los Angeles falls back.
private let fallBack: Millis = 1_793_520_000_000

private func inputs(_ clock: LocalClock) -> EstimateInputs {
    EstimateInputs(halfLifeHours: 5, targetSleepHours: 8, clock: clock)
}

@Suite struct EnergyEstimateTests {
    @Test func noSleepNeedsSleep() {
        #expect(Summary.estimateAlertness(at: now, doses: [], sleeps: [], inputs: inputs(utc)) == .needsSleep)
    }

    @Test func napsUnderThreeHoursNeedSleep() {
        let naps = [
            SleepSession(id: "manual:sleep:nap:a", start: now - 8 * hourMs, end: now - 6 * hourMs, type: .nap),
            SleepSession(id: "manual:sleep:nap:b", start: now - 4 * hourMs, end: now - 2 * hourMs, type: .nap),
        ]

        #expect(Summary.estimateAlertness(at: now, doses: [], sleeps: naps, inputs: inputs(utc)) == .needsSleep)
    }

    @Test func mainSleepOlderThanEighteenHoursNeedsSleep() {
        let sleep = SleepSession(
            id: "manual:sleep:old:a",
            start: now - 26 * hourMs - 1,
            end: now - 18 * hourMs - 1
        )

        #expect(Summary.estimateAlertness(at: now, doses: [], sleeps: [sleep], inputs: inputs(utc)) == .needsSleep)
    }

    @Test func exactlyThreeHoursCountsAsMainSleep() {
        let sleep = SleepSession(id: "manual:sleep:boundary-duration:a", start: now - 5 * hourMs, end: now - 2 * hourMs)

        #expect(Summary.estimateAlertness(at: now, doses: [], sleeps: [sleep], inputs: inputs(utc)).score != nil)
    }

    @Test func mainSleepEndingExactlyEighteenHoursAgoStillScores() {
        let sleep = SleepSession(id: "manual:sleep:boundary-recency:a", start: now - 21 * hourMs, end: now - 18 * hourMs)

        #expect(Summary.estimateAlertness(at: now, doses: [], sleeps: [sleep], inputs: inputs(utc)).score != nil)
    }

    @Test func recentMainSleepStillScores() {
        let sleep = SleepSession(id: "manual:sleep:recent:a", start: now - 9 * hourMs, end: now - 2 * hourMs)

        #expect(Summary.estimateAlertness(at: now, doses: [], sleeps: [sleep], inputs: inputs(utc)).score != nil)
    }

    @Test func inProgressSleepOfFourHoursScores() {
        let sleep = SleepSession(id: "manual:sleep:in-progress-main", start: now - 4 * hourMs, end: now + hourMs)

        #expect(Summary.estimateAlertness(at: now, doses: [], sleeps: [sleep], inputs: inputs(utc)).score != nil)
    }

    @Test func inProgressSleepDoesNotMergeIntoRecentCompletedMainSleep() {
        let t = now
        let nightEnd = t - hourMs
        let sleeps = [
            SleepSession(id: "manual:sleep:completed-night", start: nightEnd - 7 * hourMs, end: nightEnd),
            SleepSession(id: "manual:sleep:in-progress", start: nightEnd + 20 * minuteMs, end: t + 2 * hourMs),
        ]

        #expect(Summary.estimateAlertness(at: t, doses: [], sleeps: sleeps, inputs: inputs(utc)).score != nil)
        #expect(EnergyEstimate.capture(at: t, doses: [], sleeps: sleeps, inputs: inputs(utc)).modeledScore != nil)
    }

    @Test func touchingFragmentsCountAsOneMainSleep() {
        let sleeps = [
            SleepSession(id: "manual:sleep:fragment:a", start: now - 8 * hourMs, end: now - 6 * hourMs),
            SleepSession(id: "manual:sleep:fragment:b", start: now - 6 * hourMs, end: now - 4 * hourMs),
        ]
        #expect(Summary.estimateAlertness(at: now, doses: [], sleeps: sleeps, inputs: inputs(utc)).score != nil)
    }

    @Test func briefAwakeningFragmentsCountAsRecentMainSleepInEstimateAndProjection() {
        let gap = SleepIntervals.briefAwakeningMs - 1
        let end = now - hourMs
        let secondStart = end - 90 * minuteMs
        let firstEnd = secondStart - gap
        let sleeps = [
            SleepSession(id: "healthkit:sleep:fragment:a", start: firstEnd - 2 * hourMs, end: firstEnd),
            SleepSession(id: "healthkit:sleep:fragment:b", start: secondStart, end: end),
        ]

        #expect(gap < SleepIntervals.briefAwakeningMs)
        #expect(Summary.estimateAlertness(at: now, doses: [], sleeps: sleeps, inputs: inputs(utc)).score != nil)
        #expect(EnergyEstimate.capture(at: now, doses: [], sleeps: sleeps, inputs: inputs(utc)).modeledScore != nil)
    }

    @Test func longAwakeningFragmentsDoNotCountAsMainSleep() {
        let gap = 45 * minuteMs
        let end = now - hourMs
        let secondStart = end - 2 * hourMs
        let firstEnd = secondStart - gap
        let sleeps = [
            SleepSession(id: "healthkit:sleep:long-fragment:a", start: firstEnd - 2 * hourMs, end: firstEnd),
            SleepSession(id: "healthkit:sleep:long-fragment:b", start: secondStart, end: end),
        ]

        #expect(gap > SleepIntervals.briefAwakeningMs)
        #expect(Summary.estimateAlertness(at: now, doses: [], sleeps: sleeps, inputs: inputs(utc)) == .needsSleep)
    }

    @Test func briefAwakeningFragmentsOutsideEighteenHoursNeedSleep() {
        let gap = SleepIntervals.briefAwakeningMs - 1
        let end = now - 18 * hourMs - 1
        let secondStart = end - 90 * minuteMs
        let firstEnd = secondStart - gap
        let sleeps = [
            SleepSession(id: "healthkit:sleep:old-fragment:a", start: firstEnd - 2 * hourMs, end: firstEnd),
            SleepSession(id: "healthkit:sleep:old-fragment:b", start: secondStart, end: end),
        ]

        #expect(gap < SleepIntervals.briefAwakeningMs)
        #expect(Summary.estimateAlertness(at: now, doses: [], sleeps: sleeps, inputs: inputs(utc)) == .needsSleep)
    }

    @Test func overlappingPhoneAndWatchSleepCountsOnceForEligibilityAndScore() {
        let watch = SleepSession(id: "healthkit:sleep:watch", start: now - 9 * hourMs, end: now - 2 * hourMs)
        let phone = SleepSession(id: "healthkit:sleep:phone", start: now - 9 * hourMs + minuteMs, end: now - 2 * hourMs + minuteMs)
        let alone = Summary.estimateAlertness(at: now, doses: [], sleeps: [watch], inputs: inputs(utc))
        let phoneAlone = Summary.estimateAlertness(at: now, doses: [], sleeps: [phone], inputs: inputs(utc))
        let duplicate = Summary.estimateAlertness(at: now, doses: [], sleeps: [watch, phone], inputs: inputs(utc))
        #expect(alone.score != nil)
        #expect(phoneAlone.score == alone.score)
        #expect(duplicate.score == alone.score)
    }

    @Test func needsSleepCopyIsAccessibleAcrossEnergyAndAssistantSurfaces() throws {
        let text = Summary.describe(.needsSleep)
        #expect(text.localizedCaseInsensitiveContains("unavailable"))
        #expect(text.contains("at least 3 hours") && text.contains("18 hours"))
        #expect(text.replacingOccurrences(of: "18", with: "").replacingOccurrences(of: "3", with: "").filter(\.isNumber).isEmpty)

        let energy = EnergyEstimate.capture(at: now, doses: [], sleeps: [], inputs: inputs(utc))
        #expect(energy.modeledScore == nil)
        #expect(energy.summary.localizedCaseInsensitiveContains("unavailable"))
        #expect(energy.summary.localizedCaseInsensitiveContains("sleep"))
        #expect(energy.summary.replacingOccurrences(of: "18", with: "").replacingOccurrences(of: "3", with: "").filter(\.isNumber).isEmpty)

        for kind in [AssistantCard.Kind.energy, .briefing] {
            let card = AssistantCards.make(kind, state: AppState(), now: now, clock: utc, text: .localized(locale: Locale(identifier: "en_US"), timeZone: utc.timeZone))
            let metric = try #require(card.metrics.first { $0.id == "alertness" })
            #expect(metric.label == "Modeled alertness")
            #expect(metric.value == "Needs sleep")
            #expect(metric.source == "Modeled")
            #expect(metric.detail == energy.summary)
            let accessibilityLabel = [metric.label, metric.value, metric.source, metric.detail].filter { !$0.isEmpty }.joined(separator: ". ")
            #expect(accessibilityLabel.localizedCaseInsensitiveContains("needs sleep"))
            #expect(accessibilityLabel.replacingOccurrences(of: "18", with: "").replacingOccurrences(of: "3", with: "").filter(\.isNumber).isEmpty)
        }
    }

    @Test func matchesTheExistingEstimateForEveryFixtureProbe() throws {
        var probes = 0
        for context in try ParityTests.contexts() {
            for probe in context.scenario.list("alertness") {
                let t = try #require(probe.double("t"))
                let existing = Summary.estimateAlertness(at: t, doses: context.doses, sleeps: context.sleeps, inputs: context.inputs)
                let energy = EnergyEstimate.capture(at: t, doses: context.doses, sleeps: context.sleeps, inputs: context.inputs)
                #expect(energy.modeledScore == existing.score)
                #expect(energy.timeZoneIdentifier == context.clock.timeZone.identifier)
                #expect(energy.evidence.activeCaffeineMg == Caffeine.activeMg(at: t, doses: context.doses, halfLifeHours: 5))
                #expect(energy.includesSample == energy.evidence.includesSample)
                switch existing {
                case .needsSleep:
                    #expect(energy.contributions.isEmpty && energy.unroundedScore == nil)
                    #expect(energy.missingInputs.contains(.recentSleep))
                case .estimated(let score, let hours, let sample):
                    let raw = Alertness.score(at: t, doses: context.doses, sleeps: context.sleeps, halfLifeHours: 5, targetSleepHours: 8, clock: context.clock)
                    #expect(energy.unroundedScore == raw)
                    #expect(jsRoundInt(try #require(energy.unroundedScore)) == score)
                    #expect(energy.contributions.map(\.kind) == EnergyContribution.Kind.allCases)
                    #expect(energy.sleepHoursLast24 == hours)
                    // Older sample caffeine can flag the snapshot where the
                    // 24-hour summary flag does not; never the reverse.
                    #expect(!sample || energy.includesSample)
                    #expect(!energy.missingInputs.contains(.recentSleep))
                }
                probes += 1
            }
        }
        #expect(probes > 0)
    }

    @Test func missingSleepHasNoScoreInBothZones() {
        let doses = [Dose(id: "a", timestamp: now - hourMs, mg: 95)]
        let sleeps = [SleepSession(id: "manual:sleep:1:a", start: now - 40 * hourMs, end: now - 32 * hourMs)]
        for clock in [utc, pacific] {
            let energy = EnergyEstimate.capture(at: now, doses: doses, sleeps: sleeps, inputs: inputs(clock))
            #expect(Summary.estimateAlertness(at: now, doses: doses, sleeps: sleeps, inputs: inputs(clock)) == .needsSleep)
            #expect(energy.modeledScore == nil && energy.contributions.isEmpty)
            #expect(energy.missingInputs == [.recentSleep])
            #expect(energy.summary.hasPrefix("Modeled alertness unavailable."))
        }
    }

    @Test func snapshotRecordsItsContextAndRoundTrips() throws {
        let sleeps = [SleepSession(id: "demo:sleep:1", start: now - 9 * hourMs, end: now - 2 * hourMs)]
        let energy = EnergyEstimate.capture(at: now, doses: [], sleeps: sleeps, inputs: inputs(pacific))
        #expect(energy.version == EnergyEstimate.currentVersion)
        #expect(energy.modelVersion == "alertness-1-main-sleep-3h-18h")
        #expect(energy.capturedAt == now && energy.timeZoneIdentifier == "America/Los_Angeles")
        #expect(energy.includesSample)
        #expect(energy.missingInputs == [.caffeine])
        #expect(energy.limitations == EnergyLimitation.allCases)
        #expect(energy.evidence.sleep.map(\.source) == [.sample])
        let decoded = try JSONDecoder().decode(EnergyEstimate.self, from: JSONEncoder().encode(energy))
        #expect(decoded == energy)
    }

    @Test func legacyModelSnapshotKeepsItsVersionAndScoreAfterRefresh() throws {
        let sleeps = [SleepSession(id: "manual:sleep:legacy", start: now - 9 * hourMs, end: now - 2 * hourMs)]
        var legacy = EnergyEstimate.capture(at: now, doses: [], sleeps: sleeps, inputs: inputs(utc))
        legacy.modelVersion = "alertness-1"
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let stored = try encoder.encode(legacy)
        let decoded = try JSONDecoder().decode(EnergyEstimate.self, from: stored)
        let refreshed = EnergyEstimate.capture(at: now, doses: [], sleeps: sleeps, inputs: inputs(utc))
        #expect(decoded == legacy)
        #expect(decoded.modeledScore == refreshed.modeledScore)
        #expect(decoded.modelVersion != refreshed.modelVersion)
        let projection = EnergyProjection.build(now: now, doses: [], sleeps: sleeps, inputs: inputs(utc))
        #expect(projection.modelVersion == refreshed.modelVersion)
        #expect(try encoder.encode(decoded) == stored)
    }

    @Test func timeOfDayFollowsTheLocalClockAcrossFallBack() {
        let sleeps = [SleepSession(id: "manual:sleep:1:a", start: fallBack - 6 * hourMs, end: fallBack - 3 * hourMs)]
        // 1:30 AM PDT and 1:30 AM PST are an hour apart and share the local hour.
        let first = EnergyEstimate.capture(at: fallBack + 30 * minuteMs, doses: [], sleeps: sleeps, inputs: inputs(pacific))
        let second = EnergyEstimate.capture(at: fallBack + 90 * minuteMs, doses: [], sleeps: sleeps, inputs: inputs(pacific))
        #expect(first.contributions[1].term == second.contributions[1].term)
        let firstUTC = EnergyEstimate.capture(at: fallBack + 30 * minuteMs, doses: [], sleeps: sleeps, inputs: inputs(utc))
        let secondUTC = EnergyEstimate.capture(at: fallBack + 90 * minuteMs, doses: [], sleeps: sleeps, inputs: inputs(utc))
        #expect(firstUTC.contributions[1].term != secondUTC.contributions[1].term)
    }

    @Test func publicTextFollowsCopyRules() {
        let sleeps = [SleepSession(id: "manual:sleep:1:a", start: now - 9 * hourMs, end: now - 2 * hourMs)]
        let energy = EnergyEstimate.capture(at: now, doses: [], sleeps: sleeps, inputs: inputs(utc))
        let texts = [energy.summary, EnergyEstimate.title, EnergyProjection.futureAssumption, EnergyCheckIn.scaleLabel, EnergyCheckIn.kindLabel]
            + EnergyMissingInput.allCases.map(\.text) + EnergyLimitation.allCases.map(\.text)
        for text in texts {
            #expect(CopyRules.violations(in: text).isEmpty, "\(text)")
            #expect(!text.contains("%"))
        }
        #expect(EnergyEstimate.title == "Modeled alertness")
        #expect(EnergyLimitation.unmeasuredFactors.text.contains("Illness, stress"))
        #expect(!EnergyLimitation.unmeasuredFactors.text.contains("because"))
    }

    let recentSleep = [SleepSession(id: "manual:sleep:1:a", start: now - 9 * hourMs, end: now - 2 * hourMs)]

    @Test func caffeineOlderThanADayStillCountsAndIsListed() throws {
        for clock in [utc, pacific] {
            for id in ["lx1-old", "demo:dose:old"] {
                let doses = [Dose(id: id, timestamp: now - 30 * hourMs, mg: 200, source: "Drip")]
                let energy = EnergyEstimate.capture(at: now, doses: doses, sleeps: recentSleep, inputs: inputs(clock))
                let existing = Summary.estimateAlertness(at: now, doses: doses, sleeps: recentSleep, inputs: inputs(clock))
                #expect(energy.modeledScore == existing.score)
                #expect(energy.missingInputs == [.recentCaffeine])
                #expect(!energy.missingInputs.contains(.caffeine))
                let input = try #require(energy.evidence.caffeine.first)
                #expect(energy.evidence.caffeine.count == 1 && energy.evidence.fadedCaffeine == nil)
                #expect(input.recordID == id && input.timestamp == now - 30 * hourMs && input.mg == 200)
                #expect(input.activeMg == 200 * pow(0.5, 6) && energy.evidence.activeCaffeineMg == input.activeMg)
                #expect(try #require(energy.contributions.first { $0.kind == .caffeine }).term > 0)
                // The 24-hour summary flag misses this dose; the snapshot doesn't.
                if case .estimated(_, _, let summarySample) = existing { #expect(!summarySample) }
                #expect(energy.includesSample == (id == "demo:dose:old"))
                #expect(input.source == (id == "demo:dose:old" ? .sample : .manual))
            }
        }
    }

    @Test func olderHealthCaffeineKeepsItsProvenance() throws {
        let provenance = HealthSampleProvenance(sampleUUID: "ABCD-1", sourceBundleIdentifier: "com.example.tracker", sourceName: "Tracker")
        let dose = HealthCaffeineImport.dose(from: HealthCaffeineSample(provenance: provenance, timestamp: now - 28 * hourMs, mg: 120))
        let energy = EnergyEstimate.capture(at: now, doses: [dose], sleeps: recentSleep, inputs: inputs(utc))
        let input = try #require(energy.evidence.caffeine.first)
        #expect(input.source == .health && input.recordID == "healthkit:caffeine:abcd-1")
        #expect(input.healthSampleUUID == "abcd-1" && input.healthSourceBundleIdentifier == "com.example.tracker")
        #expect(energy.missingInputs == [.recentCaffeine])
    }

    @Test func fadedAndVanishedCaffeineAreToldApart() throws {
        let faded = [Dose(id: "demo:dose:month", timestamp: now - 30 * dayMs, mg: 100)]
        let energy = EnergyEstimate.capture(at: now, doses: faded, sleeps: recentSleep, inputs: inputs(utc))
        let summary = try #require(energy.evidence.fadedCaffeine)
        #expect(energy.evidence.caffeine.isEmpty)
        #expect(summary.count == 1 && summary.activeMg > 0 && summary.activeMg < EnergyEvidence.itemizedMinimumMg)
        #expect(summary.includesSample && energy.includesSample)
        #expect(energy.missingInputs == [.recentCaffeine])

        // 1,920 half-lives: the model's own arithmetic adds exactly zero.
        let vanished = [Dose(id: "demo:dose:old", timestamp: now - 400 * dayMs, mg: 100)]
        let none = EnergyEstimate.capture(at: now, doses: vanished, sleeps: recentSleep, inputs: inputs(utc))
        #expect(Caffeine.activeMg(at: now, doses: vanished, halfLifeHours: 5) == 0)
        #expect(none.missingInputs == [.caffeine] && !none.evidence.hasActiveCaffeine && !none.includesSample)
    }

    @Test func sleepEvidenceNamesTheWindowAndTheLatestEpisode() throws {
        let sleeps = [
            SleepSession(id: "healthkit:sleep:1:2", start: now - 5 * hourMs, end: now - 2 * hourMs),
            SleepSession(id: "manual:sleep:2:b", start: now - 2 * hourMs + 10 * minuteMs, end: now - 30 * minuteMs),
            SleepSession(id: "demo:sleep:old", start: now - 30 * hourMs, end: now - 23 * hourMs),
            SleepSession(id: "demo:sleep:older", start: now - 50 * hourMs, end: now - 45 * hourMs),
        ]
        let energy = EnergyEstimate.capture(at: now, doses: [], sleeps: sleeps, inputs: inputs(utc))
        #expect(energy.evidence.sleep.map(\.recordID) == ["demo:sleep:old", "healthkit:sleep:1:2", "manual:sleep:2:b"])
        #expect(energy.evidence.sleep.map(\.source) == [.sample, .health, .manual])
        #expect(energy.evidence.sleep.map(\.hoursInWindow) == [1, 3, 80.0 / 60])
        #expect(energy.evidence.sleep.map(\.inLatestEpisode) == [false, true, true])
        #expect(energy.evidence.lastWakeAt == now - 30 * minuteMs)
        #expect(try #require(energy.contributions.last).term > 0)
        #expect(energy.includesSample)
    }

    @Test func snapshotsFreezeTheirInputsAndEncodeDeterministically() throws {
        var state = AppState()
        state.sleeps = recentSleep
        state.addDose(Dose(id: "lx1-a", timestamp: now - 26 * hourMs, mg: 95, source: "Drip"))
        state.addDose(Dose(id: "lx1-b", timestamp: now - hourMs, mg: 60, source: "Espresso"))
        let snapshot = EnergyEstimate.capture(at: now, doses: state.doses, sleeps: state.sleeps, inputs: inputs(pacific))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let stored = try encoder.encode(snapshot)

        // Input order doesn't change the snapshot.
        let reversed = EnergyEstimate.capture(at: now, doses: state.doses.reversed(), sleeps: state.sleeps, inputs: inputs(pacific))
        #expect(try encoder.encode(reversed) == stored)

        state.updateDose(id: "lx1-b", timestamp: now - hourMs, mg: 200, source: "Energy", note: nil)
        state.removeDose(id: "lx1-a")
        state.sleeps = []
        let decoded = try JSONDecoder().decode(EnergyEstimate.self, from: stored)
        #expect(decoded == snapshot)
        #expect(decoded.evidence.caffeine.map(\.recordID) == ["lx1-a", "lx1-b"])
        #expect(decoded.evidence.caffeine.map(\.mg) == [95, 60])
        #expect(decoded.evidence.sleep.map(\.recordID) == ["manual:sleep:1:a"])
        #expect(EnergyEstimate.capture(at: now, doses: state.doses, sleeps: state.sleeps, inputs: inputs(pacific)) != decoded)

        // Only plain values are stored: no Health objects or other context.
        let object = try #require(JSONSerialization.jsonObject(with: stored) as? [String: Any])
        let evidence = try #require(object["evidence"] as? [String: Any])
        #expect(Set(evidence.keys) == ["windowStart", "activeCaffeineMg", "caffeine", "sleep"])
        let input = try #require((evidence["caffeine"] as? [[String: Any]])?.first)
        #expect(Set(input.keys) == ["recordID", "source", "timestamp", "mg", "activeMg"])
    }
}

@Suite struct EnergyProjectionTests {
    let sleeps = [SleepSession(id: "manual:sleep:1:a", start: now - 10 * hourMs, end: now - 2 * hourMs)]
    let doses = [Dose(id: "a", timestamp: now - hourMs, mg: 95)]

    @Test func coversTwentyFourHoursEveryThirtyMinutesWithACurrentMarker() {
        let projection = EnergyProjection.build(now: now, doses: doses, sleeps: sleeps, inputs: inputs(pacific))
        #expect(projection.points.count == 50) // 49 grid points plus now.
        #expect(projection.points.first?.t == (now / EnergyProjection.stepMs).rounded(.down) * EnergyProjection.stepMs - 12 * hourMs)
        #expect(projection.points.last!.t - projection.points.first!.t == 24 * hourMs)
        #expect(projection.points.map(\.t) == projection.points.map(\.t).sorted())
        #expect(projection.current.t == now && projection.current.kind == .current)
        #expect(projection.points.filter { $0.kind == .current }.count == 1)
        #expect(projection.points.allSatisfy { $0.kind == ($0.t < now ? .modeledPast : ($0.t == now ? .current : .projected)) })
        let snapshot = EnergyEstimate.capture(at: now, doses: doses, sleeps: sleeps, inputs: inputs(pacific))
        #expect(projection.current.modeledScore == snapshot.modeledScore)
    }

    @Test func nowOnTheGridIsNotDuplicated() {
        let onGrid = (now / EnergyProjection.stepMs).rounded(.down) * EnergyProjection.stepMs
        let projection = EnergyProjection.build(now: onGrid, doses: doses, sleeps: sleeps, inputs: inputs(utc))
        #expect(projection.points.count == 49)
        #expect(projection.currentIndex == 24 && projection.current.t == onGrid)
    }

    @Test func usesOnlyRecordsKnownAtCaptureAndAddsNothingAhead() {
        let base = EnergyProjection.build(now: now, doses: doses, sleeps: sleeps, inputs: inputs(utc))
        let laterDose = Dose(id: "later", timestamp: now + 2 * hourMs, mg: 200)
        let unfinishedSleep = SleepSession(id: "healthkit:sleep:x", start: now - hourMs, end: now + 3 * hourMs)
        let withFuture = EnergyProjection.build(now: now, doses: doses + [laterDose], sleeps: sleeps + [unfinishedSleep], inputs: inputs(utc))
        #expect(withFuture.points == base.points)
        for point in base.points {
            let expected = EnergyEstimate.capture(at: point.t, doses: doses, sleeps: sleeps, inputs: inputs(utc))
            #expect(point.modeledScore == expected.modeledScore)
        }
        // With no further sleep assumed, the far end loses its recent sleep.
        let late = EnergyProjection.build(now: now + 14 * hourMs, doses: doses, sleeps: sleeps, inputs: inputs(utc))
        #expect(late.points.last?.modeledScore == nil)
        #expect(late.points.last?.kind == .projected)
    }

    @Test func spacingStaysThirtyMinutesAcrossFallBackAndRoundTrips() throws {
        let sleeps = [SleepSession(id: "demo:sleep:1", start: fallBack - 8 * hourMs, end: fallBack - hourMs)]
        let projection = EnergyProjection.build(now: fallBack, doses: [], sleeps: sleeps, inputs: inputs(pacific))
        let times = projection.points.map(\.t)
        #expect(zip(times, times.dropFirst()).allSatisfy { $1 - $0 == EnergyProjection.stepMs })
        #expect(projection.points.contains { $0.includesSample })
        #expect(projection.timeZoneIdentifier == "America/Los_Angeles")
        let decoded = try JSONDecoder().decode(EnergyProjection.self, from: JSONEncoder().encode(projection))
        #expect(decoded == projection)
        #expect(EnergyProjection.build(now: fallBack, doses: [], sleeps: sleeps, inputs: inputs(pacific)) == projection)
    }
}

@Suite struct EnergyCheckInTests {
    @Test func validatesTheLabeledScaleAndTime() {
        #expect(EnergyCheckIn.validate(rating: 0, recordedAt: now, now: now).message != nil)
        #expect(EnergyCheckIn.validate(rating: 6, recordedAt: now, now: now).message != nil)
        #expect(EnergyCheckIn.validate(rating: 3, recordedAt: now + 1, now: now) == .invalid("Time cannot be in the future."))
        #expect(EnergyCheckIn.validate(rating: 3, recordedAt: .nan, now: now).message != nil)
        #expect(EnergyCheckIn.validate(rating: 1, recordedAt: now, now: now) == .valid)
        #expect(EnergyCheckIn.scale.map { EnergyCheckIn.label(forRating: $0) ?? "" } == ["Very low", "Low", "Moderate", "High", "Very high"])
        #expect(EnergyCheckIn.label(forRating: 0) == nil)
    }

    @Test func appStateStoresValidCheckInsNewestFirst() {
        var state = AppState()
        let older = EnergyCheckIn(id: RecordID.newEnergyCheckInID(now: now - hourMs, entropy: "a"), recordedAt: now - hourMs, rating: 2)
        let newer = EnergyCheckIn(id: RecordID.newEnergyCheckInID(now: now, entropy: "b"), recordedAt: now, rating: 4, note: "after walk")
        #expect(older.id == "checkin:\(Int64(now - hourMs)):a")
        #expect(state.addEnergyCheckIn(older, now: now) == .valid)
        #expect(state.addEnergyCheckIn(newer, now: now) == .valid)
        #expect(state.addEnergyCheckIn(newer, now: now) != .valid)
        #expect(state.addEnergyCheckIn(EnergyCheckIn(id: "checkin:x", recordedAt: now, rating: 9), now: now) != .valid)
        #expect(state.energyCheckIns == [newer, older])
        state.removeEnergyCheckIn(id: older.id)
        #expect(state.energyCheckIns == [newer])
        state.deleteAllData()
        #expect(state.energyCheckIns.isEmpty)
    }

    @Test func checkInsAreNotPartOfTheModel() {
        let sleeps = [SleepSession(id: "manual:sleep:1:a", start: now - 9 * hourMs, end: now - 2 * hourMs)]
        var state = AppState()
        state.sleeps = sleeps
        let before = EnergyEstimate.capture(at: now, doses: state.doses, sleeps: state.sleeps, inputs: inputs(utc))
        state.addEnergyCheckIn(EnergyCheckIn(id: "checkin:1:a", recordedAt: now, rating: 1), now: now)
        #expect(EnergyEstimate.capture(at: now, doses: state.doses, sleeps: state.sleeps, inputs: inputs(utc)) == before)
    }

    @Test func oldFilesDecodeAndAStoredOutOfRangeRatingDoesNotBreakTheState() throws {
        let old = try JSONDecoder().decode(AppState.self, from: Data(#"{"schemaVersion":1,"doses":[]}"#.utf8))
        #expect(old.energyCheckIns.isEmpty && old.healthLedger == .empty && old.schemaVersion == 1)
        #expect(try StateMigration.storedVersion(Data("{}".utf8)) == 1)
        let odd = try JSONDecoder().decode(AppState.self, from: Data(#"{"schemaVersion":2,"energyCheckIns":[{"id":"checkin:1:a","recordedAt":1,"rating":42}]}"#.utf8))
        #expect(odd.energyCheckIns.first?.rating == 42)
        #expect(odd.energyCheckIns.first?.validate(now: now) != .valid)
    }
}

@Suite struct HealthCaffeineTests {
    func sample(_ uuid: String, at t: Millis = now - hourMs, mg: Double = 80, bundle: String = "com.example.tracker", sync: String? = nil) -> HealthCaffeineSample {
        HealthCaffeineSample(
            provenance: HealthSampleProvenance(sampleUUID: uuid, sourceBundleIdentifier: bundle, sourceName: "Tracker", syncIdentifier: sync, syncVersion: sync == nil ? nil : 1),
            timestamp: t, mg: mg
        )
    }

    @Test func identityIsTheSampleUUIDNeverTimeAndAmount() {
        var state = AppState()
        state.addDose(Dose(id: "manual-1", timestamp: now - hourMs, mg: 80, source: "Drip"))
        let a = sample("AAAA-1"), b = sample("bbbb-2")
        let result = state.applyHealthCaffeine(HealthCaffeineChanges(added: [a, b], deletedSampleUUIDs: [], anchor: Data([1])), now: now)
        #expect(result.upserted == 2)
        #expect(state.doses.map(\.id) == ["manual-1", "healthkit:caffeine:aaaa-1", "healthkit:caffeine:bbbb-2"])
        #expect(state.doses[1].health?.sourceBundleIdentifier == "com.example.tracker")
        #expect(state.doses[1].health?.sampleUUID == "aaaa-1")
        #expect(state.healthLedger.anchor(for: .caffeine)?.data == Data([1]))

        var edited = a
        edited.mg = 120
        state.applyHealthCaffeine(HealthCaffeineChanges(added: [edited], deletedSampleUUIDs: ["BBBB-2"], anchor: Data([2])), now: now)
        #expect(state.doses.map(\.id) == ["manual-1", "healthkit:caffeine:aaaa-1"])
        #expect(state.doses[1].mg == 120)
        #expect(state.healthLedger.anchors.count == 1 && state.healthLedger.anchor(for: .caffeine)?.data == Data([2]))
    }

    @Test func ownExportsWithALocalDoseAndInvalidSamplesAreNotImported() {
        var state = AppState()
        state.addDose(Dose(id: "m1", timestamp: now - hourMs, mg: 80))
        state.addDose(Dose(id: "m2", timestamp: now - hourMs, mg: 60))
        state.healthLedger.ownExports = [HealthOwnExport(doseID: "m2", syncIdentifier: HealthOrigin.syncIdentifier(forDoseID: "m2"), syncVersion: 1, sampleUUID: "uuid-2")]
        let result = state.applyHealthCaffeine(HealthCaffeineChanges(added: [
            sample("1", bundle: HealthOrigin.appBundleIdentifier, sync: HealthOrigin.syncIdentifier(forDoseID: "m1")),
            // Known by the UUID Health returned for Aurora's save.
            sample("UUID-2", bundle: "com.apple.health"),
            sample("3", mg: 0),
            sample("4", at: .nan),
        ], deletedSampleUUIDs: [], anchor: Data()), now: now)
        #expect(state.doses.map(\.id) == ["m1", "m2"])
        #expect(result.skippedOwn == 2 && result.rejected == 2 && result.upserted == 0)
    }

    @Test func thirdPartyMetadataNeverMakesASampleAurorasOwn() {
        var state = AppState()
        state.addDose(Dose(id: "m1", timestamp: now - hourMs, mg: 80))
        let colliding = [
            sample("t1", sync: HealthOrigin.syncIdentifier(forDoseID: "m1")),
            sample("t2", bundle: HealthOrigin.appBundleIdentifier + ".lookalike", sync: HealthOrigin.syncIdentifier(forDoseID: "m1")),
            sample("t3", bundle: "com.nmapaye.aurorafan", sync: HealthOrigin.syncIdentifierPrefix + "other"),
        ]
        for item in colliding {
            #expect(!HealthOrigin.isOwnExport(item.provenance, ledger: state.healthLedger))
            #expect(HealthOrigin.ownership(of: item.provenance, ledger: state.healthLedger, doses: state.doses) == .thirdParty)
        }
        let result = state.applyHealthCaffeine(HealthCaffeineChanges(added: colliding, deletedSampleUUIDs: [], anchor: Data()), now: now)
        #expect(result.upserted == 3 && result.skippedOwn == 0 && result.keptOwnWithoutLocalDose == 0)
        #expect(state.doses.map(\.id) == ["m1", "healthkit:caffeine:t1", "healthkit:caffeine:t2", "healthkit:caffeine:t3"])
        #expect(state.doses.dropFirst().allSatisfy { !CaffeineLog.isEditable($0) })
    }

    @Test func ownSamplesWithoutALocalDoseAreKeptReadOnlyAfterErase() {
        var state = AppState()
        state.addDose(Dose(id: "m1", timestamp: now - hourMs, mg: 80))
        state.deleteAllData()
        let own = sample("own-1", bundle: HealthOrigin.appBundleIdentifier, sync: HealthOrigin.syncIdentifier(forDoseID: "m1"))
        #expect(HealthOrigin.ownership(of: own.provenance, ledger: state.healthLedger, doses: state.doses) == .ownWithoutLocalDose)
        let result = state.applyHealthCaffeine(HealthCaffeineChanges(added: [own], deletedSampleUUIDs: [], anchor: Data()), now: now)
        #expect(result.upserted == 1 && result.keptOwnWithoutLocalDose == 1 && result.skippedOwn == 0)
        #expect(state.doses.map(\.id) == ["healthkit:caffeine:own-1"])
        #expect(state.doses[0].health?.sourceBundleIdentifier == HealthOrigin.appBundleIdentifier)
        #expect(!CaffeineLog.isEditable(state.doses[0]))
    }

    @Test func healthCaffeineIsReadOnlyAtEveryMutation() {
        var state = AppState()
        state.applyHealthCaffeine(HealthCaffeineChanges(added: [sample("u1")], deletedSampleUUIDs: [], anchor: Data()), now: now)
        let imported = state.doses[0]
        state.updateDose(id: imported.id, timestamp: 1, mg: 1, source: "Tea", note: "x")
        state.updateDose(id: imported.id, with: Dose(id: "", timestamp: 2, mg: 2))
        state.removeDose(id: imported.id)
        #expect(state.doses == [imported])
        #expect(!CaffeineLog.isEditable(imported))
        #expect(CaffeineLog.sourceLabel(imported) == "Health")
        #expect(CaffeineLog.describe(imported) { _ in "T" }.contains("Health, read-only"))
        #expect(state.enqueueHealthExport(.saveCaffeine, doseID: imported.id, now: now, id: "act") == nil)
        #expect(state.enqueueHealthExport(.saveCaffeine, doseID: "demo:dose:1", now: now, id: "act") == nil)
    }

    @Test func manualDosesKeepTheirStoredKeys() throws {
        let dose = Dose(id: "m", timestamp: 1, mg: 95, source: "Drip", note: "n")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dose)) as? [String: Any]
        #expect(object.map { Set($0.keys) } == ["id", "timestamp", "mg", "source", "note"])
    }

    @Test func ledgerTracksOwnExportsPendingActionsAndOutcomes() throws {
        var state = AppState()
        state.addDose(Dose(id: "m1", timestamp: now, mg: 95))
        #expect(state.enqueueHealthExport(.deleteCaffeine, doseID: "m1", now: now, id: "d0") == nil)
        let queuedSave = state.enqueueHealthExport(.saveCaffeine, doseID: "m1", now: now, id: "s1")
        let save = try #require(queuedSave)
        #expect(save.syncIdentifier == "com.nmapaye.aurora.dose.m1" && save.syncVersion == 1)
        state.healthLedger.finish(actionID: "s1", result: .failed, message: "Offline", now: now)
        #expect(state.healthLedger.pendingActions.first?.attempts == 1)
        state.healthLedger.finish(actionID: "s1", result: .succeeded, sampleUUID: "ABC", now: now + 1)
        #expect(state.healthLedger.pendingActions.isEmpty)
        #expect(state.healthLedger.ownExport(forDoseID: "m1") == HealthOwnExport(doseID: "m1", syncIdentifier: save.syncIdentifier, syncVersion: 1, sampleUUID: "abc", exportedAt: now + 1))
        let queuedDelete = state.enqueueHealthExport(.deleteCaffeine, doseID: "m1", now: now + 2, id: "d1")
        let delete = try #require(queuedDelete)
        #expect(delete.syncVersion == 2)
        state.healthLedger.finish(actionID: "d1", result: .succeeded, now: now + 3)
        #expect(state.healthLedger.ownExports.isEmpty)
        #expect(state.healthLedger.outcomes.map(\.result) == [.failed, .succeeded, .succeeded])
        let decoded = try JSONDecoder().decode(HealthSyncLedger.self, from: JSONEncoder().encode(state.healthLedger))
        #expect(decoded == state.healthLedger)
        state.deleteAllData()
        #expect(state.healthLedger == .empty)
    }

    @Test func providerDefaultsRefuseUndeclaredOperations() async throws {
        struct SleepOnly: HealthDataProvider {
            var capabilities: HealthCapabilities { [.readSleep] }
            var isAvailable: Bool { true }
            func sleepSamples(from start: Millis, to end: Millis) async throws -> [HealthSleepSample] { [] }
        }
        let provider = SleepOnly()
        #expect(try await provider.sleepSamples(from: 0, to: 1) == [])
        await #expect(throws: HealthProviderError.unsupported("writeOwnCaffeine")) {
            try await provider.saveOwnCaffeine(HealthCaffeineWrite(doseID: "m", timestamp: 0, mg: 1, syncIdentifier: "s", syncVersion: 1))
        }
        await #expect(throws: HealthProviderError.unsupported("readCaffeineChanges")) { try await provider.caffeineChanges(after: nil) }
        await #expect(throws: HealthProviderError.unsupported("deleteOwnCaffeine")) { try await provider.deleteOwnCaffeine(syncIdentifier: "s") }
        await #expect(throws: HealthProviderError.unsupported("observeChanges")) { _ = try await provider.startObserving([.caffeine]) { _ in } }
    }
}

@Suite struct StateMigrationTests {
    struct WriteFailure: Error {}

    let directory: URL
    var stateURL: URL { directory.appendingPathComponent("state.json") }
    var sourceURL: URL { directory.appendingPathComponent("state.v1-source.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("aurora-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// A file as the version-1 build wrote it: sorted keys, no new fields.
    func v1Data() throws -> Data {
        var state = AppState()
        state.doses = [
            Dose(id: "lx1-abc", timestamp: 1_790_000_000_000, mg: 95, source: "Drip", note: "after run"),
            Dose(id: "demo:dose:1", timestamp: 1_790_000_100_000, mg: 60),
        ]
        state.sleeps = [SleepSession(id: "healthkit:sleep:1789960000000:1789990000000", start: 1_789_960_000_000, end: 1_789_990_000_000)]
        state.prefs.cutoffHour = 14
        state.appearanceMode = .dark
        state.healthSync = HealthSync(lastSyncedAt: 1_790_000_000_000, importedCount: 3, importStatus: .succeeded)
        var object = try #require(JSONSerialization.jsonObject(with: StateMigration.encode(state)) as? [String: Any])
        object["energyCheckIns"] = nil
        object["healthLedger"] = nil
        object["schemaVersion"] = 1
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Counts writes to one file across the closures `Files` copies.
    final class WriteCount: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return count
        }
    }

    /// Fails writes to `name`; with `firstOnly`, only the first one, so a
    /// restore of the original succeeds.
    func files(failingWritesTo name: String, firstOnly: Bool = false) -> StateMigration.Files {
        let standard = StateMigration.Files.standard
        let count = WriteCount()
        return StateMigration.Files(
            read: standard.read,
            write: { data, url in
                if url.lastPathComponent == name, !firstOnly || count.next() == 1 { throw WriteFailure() }
                try standard.write(data, url)
            },
            exists: standard.exists
        )
    }

    func isRestoreFailure(_ error: Error) -> Bool {
        if case StateMigration.Failure.restoreFailed = error { return true }
        return false
    }

    func doses(in data: Data) throws -> NSArray {
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(object["doses"] as? NSArray)
    }

    @Test func migratesVersionOneAndRetainsTheVerifiedSource() throws {
        let original = try v1Data()
        try original.write(to: stateURL)
        let loaded = try #require(try StateMigration.load(directory: directory))
        #expect(loaded.migratedFrom == 1 && loaded.original == original)
        #expect(loaded.state.schemaVersion == 2)
        #expect(try Data(contentsOf: sourceURL) == original)
        let v1 = try JSONDecoder().decode(AppState.self, from: original)
        #expect(loaded.state.doses == v1.doses && loaded.state.sleeps == v1.sleeps && loaded.state.prefs == v1.prefs)
        #expect(loaded.state.energyCheckIns.isEmpty && loaded.state.healthLedger == .empty)
        let saved = try Data(contentsOf: stateURL)
        #expect(try JSONDecoder().decode(AppState.self, from: saved) == loaded.state)
        #expect(try doses(in: saved).isEqual(try doses(in: original)))

        let again = try #require(try StateMigration.load(directory: directory))
        #expect(again.migratedFrom == nil && again.state == loaded.state)
        #expect(try Data(contentsOf: sourceURL) == original)
    }

    @Test func aFileWithoutAVersionIsMigratedAsVersionOne() throws {
        try Data(#"{"doses":[{"id":"a","mg":95,"timestamp":1}]}"#.utf8).write(to: stateURL)
        let loaded = try #require(try StateMigration.load(directory: directory))
        #expect(loaded.migratedFrom == 1 && loaded.state.doses == [Dose(id: "a", timestamp: 1, mg: 95)])
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test func futureAndCorruptFilesFailClosedWithoutChanges() throws {
        let future = Data(#"{"schemaVersion":3,"doses":[{"id":"a","kind":"new"}]}"#.utf8)
        try future.write(to: stateURL)
        #expect(throws: StateMigration.Failure.unsupportedVersion(3)) { try StateMigration.load(directory: directory) }
        #expect(try Data(contentsOf: stateURL) == future)

        let corrupt = Data("{oops".utf8)
        try corrupt.write(to: stateURL)
        #expect(throws: StateMigration.Failure.undecodable) { try StateMigration.load(directory: directory) }
        #expect(try Data(contentsOf: stateURL) == corrupt)
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test func failedWritesKeepTheOriginalAndRetrySucceeds() throws {
        let original = try v1Data()
        try original.write(to: stateURL)

        #expect(throws: WriteFailure.self) { try StateMigration.load(directory: directory, files: files(failingWritesTo: "state.v1-source.json")) }
        #expect(try Data(contentsOf: stateURL) == original)
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))

        #expect(throws: WriteFailure.self) { try StateMigration.load(directory: directory, files: files(failingWritesTo: "state.json", firstOnly: true)) }
        #expect(try Data(contentsOf: stateURL) == original)
        #expect(try Data(contentsOf: sourceURL) == original)

        let retried = try #require(try StateMigration.load(directory: directory))
        #expect(retried.migratedFrom == 1 && retried.state.schemaVersion == 2)
        #expect(try Data(contentsOf: sourceURL) == original)
    }

    @Test func unverifiableSaveRestoresTheOriginal() throws {
        let original = try v1Data()
        try original.write(to: stateURL)
        let standard = StateMigration.Files.standard
        let garbling = StateMigration.Files(
            read: standard.read,
            write: { data, url in try standard.write(url.lastPathComponent == "state.json" && data != original ? Data("{".utf8) : data, url) },
            exists: standard.exists
        )
        #expect(throws: StateMigration.Failure.undecodable) { try StateMigration.load(directory: directory, files: garbling) }
        #expect(try Data(contentsOf: stateURL) == original)
    }

    @Test func aFailedRestoreIsExplicitAndKeepsTheRetainedSource() throws {
        let original = try v1Data()
        try original.write(to: stateURL)
        // Every write to state.json fails, so the restore can't be confirmed.
        let error = try #require(throws: StateMigration.Failure.self) {
            try StateMigration.load(directory: directory, files: files(failingWritesTo: "state.json"))
        }
        #expect(isRestoreFailure(error))
        #expect(try Data(contentsOf: sourceURL) == original)
        #expect(try Data(contentsOf: stateURL) == original) // Atomic writes never replaced it.
    }

    @Test func aGarbledSaveWithAFailedRestoreLeavesTheSourceForRecovery() throws {
        let original = try v1Data()
        try original.write(to: stateURL)
        let standard = StateMigration.Files.standard
        let garbleThenFail = StateMigration.Files(
            read: standard.read,
            write: { data, url in
                guard url.lastPathComponent == "state.json" else { return try standard.write(data, url) }
                if data == original { throw WriteFailure() }
                try standard.write(Data("{".utf8), url)
            },
            exists: standard.exists
        )
        let error = try #require(throws: StateMigration.Failure.self) {
            try StateMigration.load(directory: directory, files: garbleThenFail)
        }
        #expect(isRestoreFailure(error))
        guard case .restoreFailed(let detail) = error else { return }
        #expect(detail.contains("retained source verified"))
        #expect(try Data(contentsOf: sourceURL) == original)

        // The next launch sees an undecodable state.json and goes to recovery;
        // the retained source is still byte-equal and decodes to every record.
        #expect(throws: StateMigration.Failure.undecodable) { try StateMigration.load(directory: directory) }
        #expect(try Data(contentsOf: sourceURL) == original)
        #expect(try StateMigration.decode(Data(contentsOf: sourceURL)) == JSONDecoder().decode(AppState.self, from: original))
    }

    @Test func aDifferentRetainedSourceIsNeverReplaced() throws {
        let original = try v1Data()
        try original.write(to: stateURL)
        let other = Data(#"{"schemaVersion":1,"doses":[]}"#.utf8)
        try other.write(to: sourceURL)
        #expect(throws: StateMigration.Failure.retainedSourceMismatch) { try StateMigration.load(directory: directory) }
        #expect(try Data(contentsOf: stateURL) == original)
        #expect(try Data(contentsOf: sourceURL) == other)
    }

    @Test func currentFilesAndMissingFilesAreNotTouched() throws {
        #expect(try StateMigration.load(directory: directory) == nil)
        let data = try StateMigration.encode(AppState())
        try data.write(to: stateURL)
        let loaded = try #require(try StateMigration.load(directory: directory))
        #expect(loaded.migratedFrom == nil && loaded.state == AppState())
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
    }
}

@MainActor
@Suite struct RefreshCoordinatorTests {
    actor Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var calls = 0

        func enter() async -> Int {
            calls += 1
            let call = calls
            await withCheckedContinuation { waiters.append($0) }
            return call
        }

        var waiting: Int { waiters.count }

        func releaseAll() {
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    @MainActor final class Applied {
        var values: [Int] = []
    }

    func waitFor(_ gate: Gate, waiting count: Int) async {
        while await gate.waiting < count { await Task.yield() }
    }

    @Test func concurrentRequestsShareOneFetch() async {
        let gate = Gate(), applied = Applied()
        let coordinator = RefreshCoordinator<Int>(fetch: { await gate.enter() }, apply: { applied.values.append($0) })
        let first = Task { await coordinator.refresh() }
        await waitFor(gate, waiting: 1)
        let joined = Applied()
        // Both run on the main actor, so once the flag is set the second call
        // has already joined the running refresh.
        let second = Task {
            joined.values.append(0)
            return await coordinator.refresh()
        }
        while joined.values.isEmpty { await Task.yield() }
        #expect(coordinator.isRefreshing)
        await gate.releaseAll()
        #expect(await first.value == .applied)
        #expect(await second.value == .applied)
        #expect(await gate.calls == 1 && applied.values == [1])
        #expect(!coordinator.isRefreshing)
    }

    @Test func invalidationDiscardsALateResultEvenIfTheFetchIgnoresCancellation() async {
        let gate = Gate(), applied = Applied()
        let coordinator = RefreshCoordinator<Int>(fetch: { await gate.enter() }, apply: { applied.values.append($0) })
        let stale = Task { await coordinator.refresh() }
        await waitFor(gate, waiting: 1)
        coordinator.invalidate()
        #expect(coordinator.generation == 1 && !coordinator.isRefreshing)
        await gate.releaseAll()
        #expect(await stale.value == .discarded)
        #expect(applied.values.isEmpty)
    }

    @Test func aNewerRefreshWinsTheRace() async {
        let gate = Gate(), applied = Applied()
        let coordinator = RefreshCoordinator<Int>(fetch: { await gate.enter() }, apply: { applied.values.append($0) })
        let stale = Task { await coordinator.refresh() }
        await waitFor(gate, waiting: 1)
        coordinator.invalidate()
        let fresh = Task { await coordinator.refresh() }
        await waitFor(gate, waiting: 2)
        #expect(coordinator.isRefreshing)
        await gate.releaseAll()
        #expect(await stale.value == .discarded)
        #expect(await fresh.value == .applied)
        #expect(applied.values == [2])
        #expect(!coordinator.isRefreshing)
    }

    @Test func failuresAreReportedOnlyWhileCurrent() async {
        struct Offline: Error {}
        let applied = Applied()
        let failing = RefreshCoordinator<Int>(fetch: { throw Offline() }, apply: { applied.values.append($0) })
        guard case .failed = await failing.refresh() else {
            Issue.record("Expected a failure")
            return
        }
        let cancelled = RefreshCoordinator<Int>(fetch: {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return 1
        }, apply: { applied.values.append($0) })
        let task = Task { await cancelled.refresh() }
        while !cancelled.isRefreshing { await Task.yield() }
        cancelled.invalidate()
        #expect(await task.value == .discarded)
        #expect(applied.values.isEmpty)
    }
}
