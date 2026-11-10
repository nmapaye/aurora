import Foundation
import Testing
@testable import AuroraCore

@Suite struct SleepImportWindowTests {
    /// The anchored Health sleep read asks only for the refresh window, so
    /// the first read reaches last night instead of paging up from the
    /// oldest sample in Health.
    @Test func anchoredReadStartsAtTheRefreshWindow() {
        let now: Millis = 1_800_000_000_000
        #expect(HealthSleepImport.anchoredReadStart(now: now) == now - HealthImport.refreshDays * dayMs)
        #expect(HealthImport.refreshDays * dayMs <= AppState.healthSleepRetentionDays * dayMs)
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
