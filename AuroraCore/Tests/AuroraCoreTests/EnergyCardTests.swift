import Foundation
import Testing
@testable import AuroraCore

private let utc = LocalClock(timeZone: TimeZone(identifier: "UTC")!)
private let pacific = LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
private let now: Millis = 1_790_527_260_000 // 2026-09-27 16:41 UTC
/// 2026-11-01 08:00 UTC: 1:00 AM PDT, an hour before Los Angeles falls back.
private let fallBack: Millis = 1_793_520_000_000
private func text(_ clock: LocalClock) -> DateText { .localized(locale: Locale(identifier: "en_US"), timeZone: clock.timeZone) }

private func state(doses: [Dose] = [], sleeps: [SleepSession] = [], checkIns: [EnergyCheckIn] = [], tests: [VigilanceSession] = []) -> AppState {
    var state = AppState()
    state.doses = doses; state.sleeps = sleeps; state.energyCheckIns = checkIns; state.vigilanceSessions = tests
    return state
}

private let night = SleepSession(id: "manual:sleep:1:a", start: now - 10 * hourMs, end: now - 3 * hourMs)

@Suite struct EnergySnapshotTests {
    @Test func scoreMatchesTheBaselineForEveryFixtureProbe() throws {
        var probes = 0
        for context in try ParityTests.contexts() {
            for probe in context.scenario.list("alertness") {
                let t = try #require(probe.double("t"))
                var s = state(doses: context.doses, sleeps: context.sleeps)
                s.prefs.halfLife = 5; s.prefs.targetSleep = 8
                // Parity on the same eligible inputs: records known at capture.
                // The scalar suite (EnergyEstimateTests) still covers every record.
                let known = EnergyProjection.knownRecords(doses: context.doses, sleeps: context.sleeps, at: t)
                let existing = Summary.estimateAlertness(at: t, doses: known.doses, sleeps: known.sleeps, inputs: context.inputs)
                let snapshot = EnergySnapshot.capture(state: s, now: t, clock: context.clock, includeProjection: false)
                #expect(snapshot.estimate.modeledScore == existing.score)
                #expect(snapshot.estimate.timeZoneIdentifier == context.clock.timeZone.identifier)
                let card = AssistantCards.make(.energy, state: s, now: t, clock: context.clock, text: text(context.clock))
                #expect(card.metrics.first { $0.id == "alertness" }?.value == existing.score.map { "\($0)" } ?? "Needs sleep")
                probes += 1
            }
        }
        #expect(probes > 0)
    }

    @Test func missingRecordsStayMissingInBothZones() throws {
        for clock in [utc, pacific] {
            let card = AssistantCards.make(.energy, state: AppState(), now: now, clock: clock, text: text(clock))
            let snapshot = try #require(card.energy)
            #expect(snapshot.estimate.modeledScore == nil && snapshot.estimate.contributions.isEmpty)
            #expect(snapshot.estimate.missingInputs == [.recentSleep, .caffeine])
            #expect(snapshot.observations.isEmpty && snapshot.checkIns.isEmpty && snapshot.reactions.isEmpty)
            #expect(card.metrics.map(\.id) == ["sleep", "caffeine", "activeCaffeine", "alertness"])
            #expect(card.metrics.filter(\.missing).count == 4)
            #expect(card.metrics.first { $0.id == "activeCaffeine" }?.value == "No record")
            let projection = AssistantCards.make(.energyProjection, state: AppState(), now: now, clock: clock, text: text(clock))
            #expect(projection.energy?.projection?.points.allSatisfy { $0.modeledScore == nil } == true)
            #expect(projection.metrics.first?.value == "Needs sleep")
        }
    }

    @Test func contributionsShowSleepCaffeineAndTimeOfDay() throws {
        let dose = Dose(id: "lx1", timestamp: now - 2 * hourMs, mg: 120, source: "Drip")
        let card = AssistantCards.make(.energy, state: state(doses: [dose], sleeps: [night]), now: now, clock: pacific, text: text(pacific))
        let estimate = try #require(card.energy?.estimate)
        #expect(estimate.contributions.map(\.kind) == EnergyContribution.Kind.allCases)
        #expect(EnergyContribution.Kind.allCases.map(\.label).allSatisfy { !$0.isEmpty && CopyRules.violations(in: $0).isEmpty })
        #expect(EnergyContribution.Kind.timeOfDay.label.contains("generic"))
        #expect(card.metrics.first { $0.id == "activeCaffeine" }?.value == "\(numberText(jsRound(estimate.evidence.activeCaffeineMg))) mg")
        #expect(card.metrics.first { $0.id == "alertness" }?.label == "Modeled alertness")
        #expect(card.metrics.first { $0.id == "alertness" }?.detail == estimate.summary)
        #expect(card.metrics.allSatisfy { CopyRules.violations(in: $0.label + " " + $0.source + " " + $0.detail).isEmpty })
        #expect(!(card.metrics.first { $0.id == "alertness" }?.value.contains("%") ?? true))
        #expect(!(card.metrics.first { $0.id == "alertness" }?.value.contains("/") ?? true))
        #expect(EnergyContribution(kind: .caffeine, term: 0.2, points: 4.6).pointsText == "+5")
        #expect(EnergyContribution(kind: .sleepDebt, term: 0.2, points: -7.5).pointsText == "−7")
        #expect(EnergyContribution(kind: .inertia, term: 0, points: -0.2).pointsText == "0")
        for copy in [EnergySnapshot.scaleNote, EnergySnapshot.separateNote] + EnergyProjection.PointKind.allLabels {
            #expect(CopyRules.violations(in: copy).isEmpty && !copy.contains("%"))
        }
    }

    @Test func sampleRecordsAreFlagged() throws {
        let sample = SleepSession(id: "demo:sleep:1", start: now - 9 * hourMs, end: now - 2 * hourMs)
        let card = AssistantCards.make(.energyProjection, state: state(sleeps: [sample]), now: now, clock: utc, text: text(utc))
        let snapshot = try #require(card.energy)
        #expect(snapshot.includesSample)
        #expect(snapshot.observations.map(\.source) == [.sample])
    }

    @Test func futureRecordsAreNotObservationsOrCurveInputs() throws {
        let future = Dose(id: "lx-future", timestamp: now + hourMs, mg: 200)
        let unfinished = SleepSession(id: "manual:sleep:2:b", start: now - hourMs, end: now + 2 * hourMs)
        let with = AssistantCards.make(.energyProjection, state: state(doses: [future], sleeps: [night, unfinished]), now: now, clock: pacific, text: text(pacific))
        let without = AssistantCards.make(.energyProjection, state: state(sleeps: [night]), now: now, clock: pacific, text: text(pacific))
        #expect(with.energy?.observations.map(\.id) == [night.id])
        #expect(with.energy?.projection?.points == without.energy?.projection?.points)
        // Projected points assume nothing new; no observation is placed after capture.
        let snapshot = try #require(with.energy)
        #expect(snapshot.observations.allSatisfy { $0.end <= now })
        #expect(snapshot.projection?.points.filter { $0.t > now }.allSatisfy { $0.kind == .projected } == true)
    }

    /// Headline, metrics, evidence, observations, sample status and the
    /// current curve point all come from records known at capture.
    @Test(arguments: [
        ("ongoing only", [SleepSession(id: "manual:sleep:9:o", start: now - 2 * hourMs, end: now + hourMs)], [Dose]()),
        ("completed plus ongoing", [night, SleepSession(id: "healthkit:sleep:sample:o", start: now - hourMs, end: now + 2 * hourMs)], [Dose]()),
        ("entirely future", [SleepSession(id: "manual:sleep:9:f", start: now + hourMs, end: now + 8 * hourMs)], [Dose(id: "lx-f", timestamp: now + 30 * minuteMs, mg: 150)]),
        ("sample future", [night, SleepSession(id: "demo:sleep:f", start: now - hourMs, end: now + 5 * hourMs)], [Dose(id: "demo:dose:f", timestamp: now + hourMs, mg: 80)]),
    ]) func oneKnownInputSetAcrossTheCard(name: String, sleeps: [SleepSession], doses: [Dose]) throws {
        for clock in [utc, pacific] {
            let s = state(doses: doses, sleeps: sleeps)
            let known = EnergyProjection.knownRecords(doses: doses, sleeps: sleeps, at: now)
            let eligible = state(doses: known.doses, sleeps: known.sleeps)
            let projectionCard = AssistantCards.make(.energyProjection, state: s, now: now, clock: clock, text: text(clock))
            let energyCard = AssistantCards.make(.energy, state: s, now: now, clock: clock, text: text(clock))
            let eligibleCard = AssistantCards.make(.energy, state: eligible, now: now, clock: clock, text: text(clock))
            let snapshot = try #require(projectionCard.energy)
            let projection = try #require(snapshot.projection)
            #expect(projection.current.modeledScore == snapshot.estimate.modeledScore, "\(name)")
            #expect(projection.current.includesSample == snapshot.estimate.includesSample, "\(name)")
            #expect(projectionCard.metrics.first?.value == snapshot.estimate.modeledScore.map { "\($0)" } ?? "Needs sleep", "\(name)")
            // Parity with the baseline on the same eligible inputs.
            let baseline = Summary.estimateAlertness(at: now, doses: known.doses, sleeps: known.sleeps, inputs: EstimateInputs(prefs: s.prefs, clock: clock))
            #expect(snapshot.estimate.modeledScore == baseline.score, "\(name)")
            // Future and unfinished records change nothing on the card.
            #expect(energyCard.metrics == eligibleCard.metrics, "\(name)")
            #expect(energyCard.energy == eligibleCard.energy, "\(name)")
            #expect(snapshot.estimate.missingInputs.contains(.recentSleep) == (snapshot.estimate.modeledScore == nil), "\(name)")
            #expect(snapshot.observations.allSatisfy { $0.end <= now }, "\(name)")
            #expect(Set(snapshot.observations.map(\.id)).isSubset(of: Set(known.sleeps.map(\.id) + known.doses.map(\.id))), "\(name)")
            #expect(!snapshot.observations.contains { $0.id.hasSuffix(":f") || $0.id.hasSuffix(":o") || $0.id == "lx-f" }, "\(name)")
            #expect(!snapshot.includesSample, "\(name)")
            #expect(energyCard.metrics.first { $0.id == "sleep" }?.source.contains("Sample") == false, "\(name)")
        }
    }

    @Test func overlappingSleepCountsOnceAndDrawsOnce() throws {
        let watch = SleepSession(id: "healthkit:sleep:sample:a", start: now - 10 * hourMs, end: now - 3 * hourMs)
        let phone = SleepSession(id: "healthkit:sleep:sample:b", start: now - 9 * hourMs, end: now - 2 * hourMs)
        let both = EnergySnapshot.capture(state: state(sleeps: [watch, phone]), now: now, clock: utc, includeProjection: true)
        let union = EnergySnapshot.capture(state: state(sleeps: [SleepSession(id: "manual:sleep:3:c", start: now - 10 * hourMs, end: now - 2 * hourMs)]), now: now, clock: utc, includeProjection: true)
        #expect(both.estimate.modeledScore == union.estimate.modeledScore)
        #expect(both.projection?.points.filter { $0.t >= phone.end }.map(\.modeledScore) == union.projection?.points.filter { $0.t >= phone.end }.map(\.modeledScore))
        #expect(both.observations.count == 2)
        #expect(both.mergedSleep.count == 1)
        #expect(both.mergedSleep.first?.start == now - 10 * hourMs && both.mergedSleep.first?.end == now - 2 * hourMs)
        #expect(both.observations.allSatisfy { $0.source == .health })
    }

    @Test func curveSpansTwentyFourHoursAcrossFallBack() throws {
        let sleeps = [SleepSession(id: "manual:sleep:1:a", start: fallBack - 8 * hourMs, end: fallBack - hourMs)]
        for clock in [utc, pacific] {
            let projection = try #require(EnergySnapshot.capture(state: state(sleeps: sleeps), now: fallBack + 20 * minuteMs, clock: clock, includeProjection: true).projection)
            let times = projection.points.map(\.t)
            #expect(times == times.sorted() && Set(times).count == times.count)
            #expect(times.last! - times.first! == 24 * hourMs)
            #expect(projection.current.t == fallBack + 20 * minuteMs && projection.current.kind == .current)
            #expect(projection.points.count == 50)
        }
    }

    @Test func checkInsAndTestsAreCopiedApartFromTheModel() throws {
        let rating = EnergyCheckIn(id: "checkin:1:a", recordedAt: now - hourMs, rating: 2)
        let old = EnergyCheckIn(id: "checkin:0:a", recordedAt: now - 30 * hourMs, rating: 5)
        let base = EnergySnapshot.capture(state: state(sleeps: [night]), now: now, clock: utc, includeProjection: true)
        let with = EnergySnapshot.capture(state: state(sleeps: [night], checkIns: [rating, old]), now: now, clock: utc, includeProjection: true)
        #expect(with.checkIns == [rating])
        #expect(with.estimate == base.estimate && with.projection == base.projection)
    }

    @Test func oldCardsKeepTheirSnapshotAfterRecordsChangeRefreshAndRelaunch() throws {
        var s = state(sleeps: [night])
        let original = AssistantCards.make(.energyProjection, state: s, now: now, clock: pacific, text: text(pacific))
        var conversation = ConversationState()
        conversation.messages = [.init(text: original.title, card: original)]
        let saved = try JSONEncoder().encode(conversation)
        s.doses.append(Dose(id: "lx2", timestamp: now - 30 * minuteMs, mg: 150))
        s.sleeps = []
        let refreshed = AssistantCards.make(.energyProjection, state: s, now: now + 5 * minuteMs, clock: utc, text: text(utc))
        let relaunched = try JSONDecoder().decode(ConversationState.self, from: saved)
        let kept = try #require(relaunched.messages.first?.card)
        #expect(kept == original)
        #expect(kept.timeZone == "America/Los_Angeles" && kept.energy?.estimate.timeZoneIdentifier == "America/Los_Angeles")
        #expect(kept.energy?.observations.map(\.id) == [night.id])
        #expect(refreshed.energy?.observations.map(\.id) == ["lx2"])
        #expect(refreshed.capturedAt != kept.capturedAt && refreshed.energy != kept.energy)
    }

    @Test func cardsSavedBeforeEnergySnapshotsStillDecode() throws {
        var card = AssistantCards.make(.energy, state: AppState(), now: now, clock: utc, text: text(utc))
        card.energy = nil
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any])
        object["energy"] = nil; object["checkIn"] = nil
        let decoded = try JSONDecoder().decode(AssistantCard.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == card && decoded.energy == nil && decoded.checkIn == nil)
    }
}

@Suite struct EnergyCheckInFlowTests {
    @Test func draftNeedsAnExplicitRatingAndKeepsItsID() {
        var draft = EnergyCheckInDraft.new(now: now, entropy: "x")
        #expect(draft.rating == nil && draft.checkIn == nil)
        #expect(draft.validate(now: now) == .invalid("Choose a rating from 1 to 5."))
        draft.rating = 6
        #expect(draft.validate(now: now).message != nil)
        draft.rating = 4; draft.note = "  after a walk  "
        #expect(draft.validate(now: now) == .valid)
        #expect(draft.checkIn == EnergyCheckIn(id: "checkin:\(Int64(now)):x", recordedAt: now, rating: 4, note: "after a walk"))
        draft.recordedAt = now + minuteMs
        #expect(draft.validate(now: now) == .invalid("Time cannot be in the future."))
    }

    @Test func repeatedSaveAddsOneRecord() throws {
        var s = AppState()
        var draft = EnergyCheckInDraft.new(now: now, entropy: "x"); draft.rating = 3
        let checkIn = try #require(draft.checkIn)
        let first = s.addEnergyCheckIn(checkIn, now: now)
        let second = s.addEnergyCheckIn(checkIn, now: now)
        #expect(first == .valid && second == .invalid("This check-in is already saved."))
        #expect(s.energyCheckIns == [checkIn])
    }

    @Test func editAndUndoRevalidateTheExactRecord() throws {
        var s = AppState()
        let saved = EnergyCheckIn(id: "checkin:1:a", recordedAt: now - hourMs, rating: 2)
        s.addEnergyCheckIn(saved, now: now)
        var edit = EnergyCheckInDraft.editing(saved); edit.rating = 4
        let corrected = try #require(edit.checkIn)
        let invalid = s.replaceEnergyCheckIn(EnergyCheckIn(id: saved.id, recordedAt: now, rating: 9), expecting: saved, now: now)
        #expect(invalid.message != nil)
        let replaced = s.replaceEnergyCheckIn(corrected, expecting: saved, now: now)
        #expect(replaced == .valid && s.energyCheckIns == [corrected])
        // A stale receipt can't overwrite or remove a newer version.
        let stale = s.replaceEnergyCheckIn(corrected, expecting: saved, now: now)
        let staleRemoval = s.removeEnergyCheckIn(saved)
        #expect(stale.message != nil && !staleRemoval)
        // Undo of the correction restores the previous rating.
        let restored = s.replaceEnergyCheckIn(saved, expecting: corrected, now: now)
        #expect(restored == .valid && s.energyCheckIns == [saved])
        let removed = s.removeEnergyCheckIn(saved)
        #expect(removed && s.energyCheckIns.isEmpty)
    }

    @Test func deleteAllAndExportIncludeCheckIns() {
        var s = AppState()
        s.addEnergyCheckIn(EnergyCheckIn(id: "checkin:1:a", recordedAt: now - hourMs, rating: 2, note: "a \"quote\""), now: now)
        let csv = Export.energyCheckInsCSV(s.energyCheckIns, clock: pacific)
        #expect(csv.hasPrefix("id,local_date,datetime,rating,label,note,data_source"))
        #expect(csv.contains("\"Low\"") && csv.contains("\"Your rating\"") && csv.contains("\"\"quote\"\""))
        s.deleteAllData()
        #expect(s.energyCheckIns.isEmpty)
        #expect(Export.energyCheckInsCSV([], clock: pacific) == "id,local_date,datetime,rating,label,note,data_source")
    }

    @Test func checkInCardListsTheLastWeekOnly() {
        let recent = EnergyCheckIn(id: "checkin:2:b", recordedAt: now - dayMs, rating: 3)
        let old = EnergyCheckIn(id: "checkin:1:a", recordedAt: now - 8 * dayMs, rating: 1)
        let card = AssistantCards.make(.energyCheckIn, state: state(checkIns: [recent, old]), now: now, clock: utc, text: text(utc))
        #expect(card.checkIn?.recent == [recent])
        #expect(card.summary == EnergyCheckIn.kindLabel)
        #expect(card.refreshIntent == .energyCheckIn)
    }
}

@Suite struct EnergyIntentTests {
    @Test(arguments: [
        ("Check in my energy", AssistantIntent.energyCheckIn), ("Rate my energy", .energyCheckIn),
        ("I feel 3 out of 5", .energyCheckIn), ("energy check-in", .energyCheckIn), ("check in", .energyCheckIn),
        ("Show my energy curve", .energyProjection), ("How will my energy look later today?", .energyProjection),
        ("alertness for the next 24 hours", .energyProjection),
        ("How is my energy?", .explainEnergy), ("Why am I tired?", .explainEnergy),
        ("check in my energy curve", .unsupported), ("don't check in my energy", .unsupported),
        ("check in for my flight", nil),
        // Ratings of something else are not energy check-ins.
        ("I rated that movie 4/5", nil), ("The hotel was 5 out of 5", nil), ("rated the book 3/5", nil),
        // Standalone self-ratings, including off-scale ones, open a review.
        ("4/5", .energyCheckIn), ("I'm a 2 out of 5", .energyCheckIn), ("energy 7/5", .energyCheckIn),
        ("I feel 2 out of 5 after coffee", .energyCheckIn),
        // Mixed with another request: never split or guessed.
        ("I feel 3/5 and I had 80 mg coffee", .unsupported), ("I slept badly, feel 2 out of 5", .unsupported),
        ("energy 4/5, show my energy curve", .unsupported),
    ]) func routesWithoutAModel(input: String, expected: AssistantIntent?) {
        #expect(AssistantPlanner.explicitIntent(input) == expected)
    }

    @Test func onlySelfRatingsPrefillAReview() {
        #expect(AssistantPlanner.statedSelfRating("I feel 3 out of 5") == 3)
        #expect(AssistantPlanner.statedSelfRating("energy 4/5") == 4)
        #expect(AssistantPlanner.statedSelfRating("I rated that movie 4/5") == nil)
        #expect(AssistantPlanner.isSelfRating("I feel 7 out of 5") && AssistantPlanner.statedSelfRating("I feel 7 out of 5") == nil)
        #expect(AssistantPlanner.isSelfRating("I feel 0/5") && AssistantPlanner.statedSelfRating("I feel 0/5") == nil)
        // The scalar parser itself is unchanged.
        #expect(AssistantPlanner.checkInRating("I rated that movie 4/5") == 4)
    }

    @Test func modelLabelsAreFiniteAndListed() {
        #expect(AssistantPlanner.modelIntent("energyCheckIn") == .energyCheckIn)
        #expect(AssistantPlanner.modelIntent(" energyProjection\n") == .energyProjection)
        #expect(AssistantPlanner.modelIntent("energyCheckIn rating=5") == .unsupported)
        for intent in AssistantIntent.allCases {
            #expect(AssistantPlanner.modelInstructions.contains(intent.rawValue))
        }
    }

    @Test func statedRatingsAndCorrectionsStayOnTheScale() {
        #expect(AssistantPlanner.checkInRating("I'm a 4/5 today") == 4)
        #expect(AssistantPlanner.checkInRating("7 out of 5") == nil)
        #expect(AssistantPlanner.checkInRating("I had 2 coffees") == nil)
        #expect(AssistantPlanner.checkInCorrection("actually 4") == .rating(4))
        #expect(AssistantPlanner.checkInCorrection("Make it 2.") == .rating(2))
        #expect(AssistantPlanner.checkInCorrection("3/5") == .rating(3))
        #expect(AssistantPlanner.checkInCorrection("it's 9") == .outOfScale)
        #expect(AssistantPlanner.checkInCorrection("0") == .outOfScale)
        #expect(AssistantPlanner.checkInCorrection("I had 120 mg coffee") == nil)
        #expect(AssistantPlanner.checkInCorrection("show my energy curve") == nil)
    }
}

extension EnergyProjection.PointKind {
    static var allLabels: [String] { [EnergyProjection.PointKind.modeledPast, .current, .projected].map(\.label) }
}
