import Foundation
import Testing
@testable import AuroraCore

@Suite struct GroundedLocalExplanationTests {
    let now: Millis = 1_800_000_000_000
    let clock = LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    func bundle(_ state: AppState = AppState()) -> GroundedLocalExplanation {
        .init(estimate: EnergySnapshot.capture(state: state, now: now, clock: clock, includeProjection: false).estimate)
    }

    @Test func unknownSleepIsNotZeroAndFallbackIsExplicit() {
        let b = bundle()
        #expect(b.fallback.contains("No record"))
        #expect(!b.fallback.contains("0h") && !b.fallback.contains("0 mg"))
        #expect(!b.fallback.contains("Deterministic summary") && !b.fallback.contains("not a measurement"))
        #expect(b.render(b.allowedCompositions[0])?.contains("No record") == true)
    }

    @Test func rejectUnsupportedDigitsAdviceAndChangedFacts() {
        let b = bundle()
        for generated in ["Your score is 99.", "You should drink coffee.", "You have insomnia.",
                          "Sleep is 0h.", b.allowedCompositions[0] + " Take a nap.", "[score] [invented]"] {
            #expect(b.render(generated) == nil)
        }
        #expect(b.render(b.allowedCompositions[0]) != nil)
    }

    @Test func numericStringsOnlyRenderedFromCapturedEstimatorAndSampleAlwaysLabeled() {
        var state = AppState()
        state.doses = [Dose(id: "demo:dose", timestamp: now - hourMs, mg: 95, source: "Drip")]
        let b = bundle(state)
        for composition in b.allowedCompositions {
            let rendered = b.render(composition)
            #expect(rendered?.contains("Sample Data") == true)
            #expect(rendered?.contains("[active]") == false)
            #expect(CopyRules.violations(in: rendered ?? "").isEmpty)
        }
        #expect(!b.prompt.contains("95")) // No personal amounts sent to the model.
    }
    @Test func scoreAndActiveCaffeineAreRenderedFromSameSnapshot() throws {
        var state = AppState()
        state.sleeps = [SleepSession(id: "manual:sleep:test", start: now - 9 * hourMs, end: now - 2 * hourMs)]
        state.doses = [Dose(id: "manual:dose", timestamp: now - hourMs, mg: 95, source: "Drip")]
        let estimate = EnergySnapshot.capture(state: state, now: now, clock: clock, includeProjection: false).estimate
        let b = GroundedLocalExplanation(estimate: estimate)
        let score = try #require(estimate.modeledScore)
        for composition in b.allowedCompositions {
            let rendered = try #require(b.render(composition))
            #expect(rendered.contains(String(score)))
            #expect(!rendered.contains("[") && !rendered.contains("]"))
            #expect(CopyRules.violations(in: rendered).isEmpty)
        }
        #expect(b.allowedCompositions.contains { $0.contains("[active]") })
    }

    @Test func explanationsContainActualSignedEstimatorFactorsNotOnlyScore() throws {
        var state = AppState()
        state.sleeps = [SleepSession(id: "manual:sleep:why", start: now - 6 * hourMs, end: now - 20 * minuteMs)]
        state.doses = [Dose(id: "manual:caffeine:why", timestamp: now - hourMs, mg: 95, source: "Drip")]
        let estimate = EnergySnapshot.capture(state: state, now: now, clock: clock, includeProjection: false).estimate
        let b = GroundedLocalExplanation(estimate: estimate)
        #expect(!b.factors.isEmpty)
        for fact in b.factors {
            let source = try #require(estimate.contributions.first { $0.kind == fact.kind })
            #expect(fact.signedPoints == source.pointsText)
            let composition = try #require(b.allowedCompositions.first { $0.contains(fact.placeholder) })
            let rendered = try #require(b.render(composition))
            #expect(rendered.contains(source.pointsText))
            #expect(rendered.contains("unclamped model"))
            #expect(!rendered.contains(fact.placeholder))
        }
        #expect(b.factors.contains { $0.kind == .sleepDebt })
        #expect(b.factors.contains { $0.kind == .timeOfDay })
        #expect(b.factors.contains { $0.kind == .caffeine })
        #expect(b.factors.contains { $0.kind == .inertia })
    }

    @Test func missingSleepDoesNotInventContributionsAndNoCaffeineIsNotObservedZero() {
        let empty = bundle()
        #expect(empty.factors.isEmpty)
        #expect(empty.allowedCompositions.allSatisfy { $0.contains("No record") })
        var state = AppState()
        state.sleeps = [SleepSession(id: "manual:sleep:only", start: now - 9 * hourMs, end: now - 2 * hourMs)]
        let estimate = EnergySnapshot.capture(state: state, now: now, clock: clock, includeProjection: false).estimate
        let b = GroundedLocalExplanation(estimate: estimate)
        #expect(!b.factors.contains { $0.kind == .caffeine })
        #expect(!b.prompt.contains("0 mg"))
        #expect(b.render("Caffeine caused your tiredness.") == nil)
    }

}
