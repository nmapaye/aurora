import Foundation
import Testing
@testable import AuroraCore

@Suite struct SleepImportWindowTests {
    /// The anchored Health sleep read asks only for asleep samples that
    /// overlap the refresh window. Before the fix the read had no date
    /// predicate, so everything below matched the old behaviour except the
    /// 31-day-old night.
    @Test func anchoredFilterKeepsRecentAsleepSamplesOnly() {
        let now: Millis = 1_800_000_000_000
        let filter = HealthSleepReadFilter.anchored(now: now)
        #expect(filter.windowStart == now - HealthImport.refreshDays * dayMs)
        #expect(HealthImport.refreshDays * dayMs <= AppState.healthSleepRetentionDays * dayMs)
        let lastNightREM = filter.matches(start: now - 8 * hourMs, end: now - 7 * hourMs, value: 5)
        let inBed = filter.matches(start: now - 9 * hourMs, end: now - hourMs, value: 0)
        let awake = filter.matches(start: now - 3 * hourMs, end: now - 2 * hourMs, value: 2)
        // Started before the window and ends inside it: HealthKit's overlap
        // rule (no query options) returns it whole.
        let straddling = filter.matches(start: now - 30 * dayMs - 2 * hourMs, end: now - 30 * dayMs + hourMs, value: 3)
        let oldNight = filter.matches(start: now - 31 * dayMs - 8 * hourMs, end: now - 31 * dayMs, value: 4)
        let endsAtBoundary = filter.matches(start: now - 30 * dayMs - hourMs, end: now - 30 * dayMs, value: 1)
        #expect(lastNightREM && straddling)
        #expect(!inBed && !awake)
        #expect(!oldNight && !endsAtBoundary)
        #expect([1, 3, 4, 5].allSatisfy { filter.matches(start: now - 2 * hourMs, end: now - hourMs, value: $0) })
        #expect(!filter.matches(start: .nan, end: now, value: 1))
    }

    /// The bug: years of Watch sleep, read oldest first in bounded pages,
    /// never reached last night on the first read. With the window, the
    /// first page does.
    @Test func firstAnchoredPageReachesLastNightWithYearsOfHistory() {
        let now: Millis = 1_800_000_000_000
        // Two years of nights, six stage samples each, oldest first.
        var samples: [(start: Millis, end: Millis, value: Int)] = []
        for night in stride(from: 730, through: 1, by: -1) {
            let bed = now - Double(night) * dayMs + 2 * hourMs
            for stage in 0..<6 {
                let start = bed + Double(stage) * hourMs
                samples.append((start, start + 50 * minuteMs, [3, 4, 3, 5, 3, 5][stage]))
            }
        }
        let filter = HealthSleepReadFilter.anchored(now: now)
        let firstPage = samples.filter { filter.matches(start: $0.start, end: $0.end, value: $0.value) }
            .prefix(HealthImport.anchoredPageSize)
        let lastNightStart = now - dayMs + 2 * hourMs
        #expect(firstPage.contains { $0.start >= lastNightStart })
        #expect(firstPage.allSatisfy { $0.end > now - HealthImport.refreshDays * dayMs })
    }

    /// A fragmented Watch night (stages split by short awakenings) still
    /// counts as one qualifying sleep block for the estimate.
    @Test func fragmentedNightMergesIntoOneBlock() {
        let wake: Millis = 1_800_000_000_000
        var sleeps: [SleepSession] = []
        var t = wake - 7 * hourMs
        var index = 0
        while t < wake {
            let end = min(t + 40 * minuteMs, wake)
            sleeps.append(SleepSession(id: "healthkit:sleep:sample:\(index)", start: t, end: end))
            t = end + 10 * minuteMs
            index += 1
        }
        let clock = LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let estimate = Summary.estimateAlertness(at: wake + hourMs, doses: [], sleeps: sleeps,
                                                 inputs: .init(halfLifeHours: 5, targetSleepHours: 8, clock: clock))
        #expect(estimate.score != nil)
    }
}

@Suite struct LegalCopyTests {
    /// Installs onboarded before Terms existed never saw them, and an
    /// acknowledged older version needs a new one. First run handles its own.
    @Test func existingInstallsAreAskedOnceForTheCurrentTerms() {
        var onboarding = Onboarding.defaults
        #expect(!onboarding.needsTermsAcknowledgement())
        onboarding.completed = true
        #expect(onboarding.needsTermsAcknowledgement())
        onboarding.termsAcceptedVersion = LegalCopy.version
        #expect(!onboarding.needsTermsAcknowledgement())
        onboarding.termsAcceptedVersion = LegalCopy.version - 1
        #expect(onboarding.needsTermsAcknowledgement())
        #expect(!onboarding.needsTermsAcknowledgement(currentVersion: LegalCopy.version - 1))
    }

    @Test func acknowledgingRecordsTheCurrentVersionAndSurvivesRelaunch() throws {
        var state = AppState()
        state.onboarding.completed = true
        state.acknowledgeTerms()
        #expect(state.onboarding.termsAcceptedVersion == LegalCopy.version)
        let reopened = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        #expect(!reopened.onboarding.needsTermsAcknowledgement())
    }

    @Test func termsCarryTheDisclosuresCardsNoLongerRepeat() {
        let terms = LegalCopy.terms.map(\.body).joined(separator: " ")
        let privacy = LegalCopy.privacy.map(\.body).joined(separator: " ")
        #expect(terms.contains("aren’t measurements"))
        #expect(terms.contains("Check with a doctor before medical decisions"))
        #expect(terms.contains("on-device Foundation Models"))
        #expect(privacy.contains("Apple Health is optional"))
        #expect(privacy.contains("no cloud AI service"))
        // No numbers invented in the disclosures.
        #expect(terms.range(of: #"\d+\s*%"#, options: .regularExpression) == nil)
    }

    @Test func acknowledgementIsOptionalAndBackwardCompatible() throws {
        let old = try JSONDecoder().decode(Onboarding.self, from: JSONEncoder().encode(Onboarding.defaults))
        #expect(old.termsAcceptedVersion == nil)
        var accepted = Onboarding.defaults
        accepted.termsAcceptedVersion = LegalCopy.version
        let json = String(decoding: try JSONEncoder().encode(accepted), as: UTF8.self)
        #expect(json.contains(#""termsAcceptedVersion":1"#))
        #expect(!String(decoding: try JSONEncoder().encode(Onboarding.defaults), as: UTF8.self).contains("termsAcceptedVersion"))
    }
}

@Suite struct KSSAndMissingSleepCopyTests {
    /// The check-in intent is a sleepiness self-report now; the classifier
    /// must not be told it is an energy rating.
    @Test func checkInIntentIsDescribedAsSleepiness() {
        let line = AssistantPlanner.modelInstructions.split(separator: "\n").first { $0.contains("energyCheckIn means") }
        #expect(line?.contains("sleepy") == true)
        #expect(line?.contains("energetic") == false)
        #expect(CopyRules.violations(in: AssistantPlanner.modelInstructions).isEmpty)
    }

    /// The empty "What the Model Used" section states the actual rule,
    /// including the 18-hour window, with no number shown as 0.
    @Test func missingSleepLineKeepsTheEighteenHourWindow() {
        #expect(EnergyEstimate.missingSleepLine.contains("3 hours or more"))
        #expect(EnergyEstimate.missingSleepLine.contains("in the last 18 hours"))
        #expect(!EnergyEstimate.missingSleepLine.contains("0 "))
    }
}
