import Foundation
import Testing
@testable import AuroraCore

private let utc = LocalClock(timeZone: TimeZone(identifier: "UTC")!)
private let now: Millis = 1_790_527_260_000 // 2026-09-27 16:41 UTC

/// A run started at 0 whose first cue is due at 1 000 ms (randomValue 0).
private func running() -> VigilanceTaskState {
    Vigilance.start(at: 0, randomValue: 0)
}

/// `running()` with its first cue drawn at 1 000 ms.
private func cueShown(at cue: Millis = 1_000) -> VigilanceTaskState {
    let state = Vigilance.advance(running(), at: cue, cueDrawnAt: cue, randomValue: 0)
    #expect(state.cueShownAt == cue)
    return state
}

private func session(_ id: String, completedAt: Millis, score: Int, protocolVersion: Int, median: Double = 280) -> VigilanceSession {
    // Version 1 was the 60-second test; the label reads the length from durationMs.
    let durationMs: Millis = protocolVersion == 1 ? 60_000 : 30_000
    return VigilanceSession(
        id: id, startedAt: completedAt - durationMs, completedAt: completedAt, durationMs: durationMs, trialCount: 10,
        validReactionCount: 10, falseStartCount: 0, lapseCount: 0, medianReactionMs: median, meanReactionMs: median,
        fastestReactionMs: median - 30, reactionStdDevMs: 20, score: score, rating: Vigilance.rating(for: score),
        protocolVersion: protocolVersion
    )
}

@Suite("Reaction Test state machine")
struct VigilanceStateTests {
    @Test func protocolConstants() {
        #expect(Vigilance.protocolVersion == 2)
        #expect(Vigilance.testDurationMs == 30_000)
        #expect(Vigilance.delayMs(randomValue: 0) == 1_000)
        #expect(Vigilance.delayMs(randomValue: 0.999999) == 4_000)
        #expect(Vigilance.delayMs(randomValue: 2) == 4_000)
        #expect(Vigilance.responseWindowMs == 1_000)
        #expect(Vigilance.falseStartMs == 100)
        #expect(Vigilance.lapseMs == 400)
    }

    @Test func anEarlyTapCountsAndRestartsTheWait() {
        let state = running()
        #expect(state.nextCueAt == 1_000)
        let early = Vigilance.tap(state, at: 700, randomValue: 0.5)
        #expect(early.falseStartCount == 1)
        #expect(early.falseStarts == [VigilanceFalseStart(at: 700, afterCueMs: nil)])
        #expect(early.feedback == .tooEarly(count: 1))
        // A new 1–4 s wait from the tap, not the old due time.
        #expect(early.nextCueAt == 700 + Vigilance.delayMs(randomValue: 0.5))
        #expect(early.cueShownAt == nil)
        // The old due time passing shows nothing.
        #expect(Vigilance.advance(early, at: 1_100, randomValue: 0).cueShownAt == nil)
        // Another early tap, past the double-tap window, says "(2)".
        let again = Vigilance.tap(early, at: 1_100, randomValue: 0)
        #expect(again.feedback == .tooEarly(count: 2))
        #expect(again.nextCueAt == 2_100)
        #expect(again.trials.isEmpty)
    }

    @Test func aTouchBeforeTheCueFrameIsDrawnIsEarly() {
        // The cue is due at 1 000 but its frame shows at 1 016.
        let state = Vigilance.advance(running(), at: 1_002, cueDrawnAt: 1_016, randomValue: 0)
        #expect(state.cueShownAt == 1_016)
        let tapped = Vigilance.tap(state, at: 1_010, randomValue: 0)
        #expect(tapped.falseStarts == [VigilanceFalseStart(at: 1_010)])
        #expect(tapped.cueShownAt == nil)
        #expect(tapped.nextCueAt == 2_010)
    }

    @Test func theCueIsStampedWhenDrawnWithItsLatency() {
        let state = Vigilance.advance(running(), at: 1_004, cueDrawnAt: 1_020, randomValue: 0)
        #expect(state.cueShownAt == 1_020)
        #expect(state.cueScheduledAt == 1_000)
        let answered = Vigilance.tap(state, at: 1_306, randomValue: 0)
        #expect(answered.trials == [VigilanceTrial(cueAt: 1_020, reactionMs: 286, cueLatencyMs: 20)])
        #expect(answered.feedback == .reaction(ms: 286))
        // Without a drawn time the cue is stamped when the clock saw it due.
        #expect(Vigilance.advance(running(), at: 1_007, randomValue: 0).cueShownAt == 1_007)
    }

    @Test func aSecondTapWithin300msOfAResponseIsIgnored() {
        let answered = Vigilance.tap(cueShown(), at: 1_286, randomValue: 0)
        #expect(answered.trials.count == 1)
        let bounce = Vigilance.tap(answered, at: 1_400, randomValue: 0)
        #expect(bounce.trials == answered.trials)
        #expect(bounce.falseStartCount == 0)
        #expect(bounce.feedback == .reaction(ms: 286))
        #expect(bounce.ignoredTapCount == 1)
        #expect(bounce.nextCueAt == answered.nextCueAt)
        // At 300 ms or later, a tap during the wait is a false start again.
        let later = Vigilance.tap(bounce, at: 1_586, randomValue: 0)
        #expect(later.falseStartCount == 1)
    }

    @Test func aDoubleTapWhileWaitingCountsOnce() {
        let first = Vigilance.tap(running(), at: 500, randomValue: 0)
        let second = Vigilance.tap(first, at: 620, randomValue: 0)
        #expect(second.falseStartCount == 1)
        #expect(second.nextCueAt == first.nextCueAt)
    }

    @Test(arguments: [
        (99.0, "false start"), (100.0, "valid"), (399.0, "valid"), (400.0, "lapse"), (999.0, "lapse"),
    ])
    func thresholds(reaction: Double, outcome: String) {
        let state = Vigilance.tap(cueShown(), at: 1_000 + reaction, randomValue: 0)
        let session = Vigilance.buildSession(id: "t", startedAt: 0, completedAt: 30_000, trials: state.trials, falseStarts: state.falseStarts)
        switch outcome {
        case "false start":
            #expect(state.trials.isEmpty)
            #expect(state.falseStarts == [VigilanceFalseStart(at: 1_000 + reaction, afterCueMs: reaction)])
            #expect(state.feedback == .tooEarly(count: 1))
            #expect(state.cueShownAt == nil && state.nextCueAt == 2_000 + reaction)
        case "valid":
            #expect(state.trials.map(\.reactionMs) == [reaction])
            #expect(session.validReactionCount == 1 && session.lapseCount == 0)
            #expect(state.feedback == .reaction(ms: reaction))
        default:
            #expect(state.trials.map(\.reactionMs) == [reaction])
            #expect(session.validReactionCount == 0 && session.lapseCount == 1)
            #expect(state.feedback == .reaction(ms: reaction))
        }
    }

    @Test func aMissedCueThenALateTapSaysTooLateWithoutAFalseStart() {
        let missed = Vigilance.advance(cueShown(), at: 2_000, randomValue: 0)
        #expect(missed.trials == [VigilanceTrial(cueAt: 1_000, reactionMs: nil, cueLatencyMs: 0)])
        #expect(missed.feedback == .missed)
        #expect(missed.cueShownAt == nil)
        #expect(missed.nextCueAt == 3_000)
        let late = Vigilance.tap(missed, at: 2_200, randomValue: 0)
        #expect(late.feedback == .tooLate)
        #expect(late.falseStartCount == 0)
        #expect(late.trials == missed.trials)
        #expect(late.nextCueAt == 3_000)
        // Past the grace period, a tap is early for the next cue.
        let early = Vigilance.tap(missed, at: 2_500, randomValue: 0)
        #expect(early.feedback == .tooEarly(count: 1))
    }

    @Test func aTapAtTheWindowsEndBeforeTheClockClosesItIsTooLate() {
        let late = Vigilance.tap(cueShown(), at: 2_000, randomValue: 0)
        #expect(late.trials == [VigilanceTrial(cueAt: 1_000, reactionMs: nil, cueLatencyMs: 0)])
        #expect(late.feedback == .tooLate)
        #expect(late.falseStartCount == 0)
        #expect(late.nextCueAt == 3_000)
    }

    @Test func aTouchInsideTheWindowProcessedAfterTheClockClosedItStillCounts() {
        // The frame clock closed the window at 2 004; the touch-down was at
        // 1 990 but its event arrives after.
        let closed = Vigilance.advance(cueShown(), at: 2_004, randomValue: 0)
        #expect(closed.trials.last?.reactionMs == nil)
        let answered = Vigilance.tap(closed, at: 1_990, randomValue: 0)
        #expect(answered.trials == [VigilanceTrial(cueAt: 1_000, reactionMs: 990, cueLatencyMs: 0)])
        #expect(answered.feedback == .reaction(ms: 990))
        #expect(answered.falseStartCount == 0)
    }

    @Test func theRunEndsAt30Seconds() {
        var state = running()
        state.nextCueAt = 40_000
        #expect(Vigilance.advance(state, at: 29_999, randomValue: 0).phase == .running)
        let ended = Vigilance.advance(state, at: 30_000, randomValue: 0)
        #expect(ended.phase == .complete)
        #expect(ended.nextCueAt == nil)
        // Taps after the end change nothing.
        #expect(Vigilance.tap(ended, at: 30_100, randomValue: 0) == ended)
    }

    @Test func aCueOnScreenAt30SecondsKeepsItsWindow() {
        var state = running()
        state.nextCueAt = 29_800
        state = Vigilance.advance(state, at: 29_800, cueDrawnAt: 29_800, randomValue: 0)
        let atEnd = Vigilance.advance(state, at: 30_000, randomValue: 0)
        #expect(atEnd.phase == .running && atEnd.cueShownAt == 29_800)
        let answered = Vigilance.tap(atEnd, at: 30_090, randomValue: 0)
        #expect(answered.trials.map(\.reactionMs) == [290])
        #expect(Vigilance.advance(answered, at: 30_100, randomValue: 0).phase == .complete)
        // Unanswered, the cue becomes a missed lapse and the run ends.
        let unanswered = Vigilance.advance(atEnd, at: 30_800, randomValue: 0)
        #expect(unanswered.phase == .complete)
        #expect(unanswered.trials == [VigilanceTrial(cueAt: 29_800, reactionMs: nil, cueLatencyMs: 0)])
    }

    @Test func aTypicalRunHasAboutTenTrials() {
        for (random, reaction) in [(0.5, 280.0), (0.0, 250.0), (0.999999, 350.0)] {
            var state = Vigilance.start(at: 0, randomValue: random)
            var t: Millis = 0
            while state.phase == .running && t < 40_000 {
                t += 1
                state = Vigilance.advance(state, at: t, cueDrawnAt: t, randomValue: random)
                if let cue = state.cueShownAt, t == cue + reaction {
                    state = Vigilance.tap(state, at: t, randomValue: random)
                }
            }
            #expect(state.phase == .complete)
            #expect(state.trials.allSatisfy { $0.reactionMs == reaction })
            #expect((6...25).contains(state.trials.count), "random \(random): \(state.trials.count)")
            if random == 0.5 { #expect((9...11).contains(state.trials.count)) }
        }
    }

    @Test func closeConfirmationPausesTheClock() {
        let shown = cueShown()
        let paused = Vigilance.pause(shown, at: 1_200)
        // While paused nothing moves and taps don't count.
        #expect(Vigilance.advance(paused, at: 9_000, randomValue: 0) == paused)
        #expect(Vigilance.tap(paused, at: 1_300, randomValue: 0) == paused)
        let resumed = Vigilance.resume(paused, at: 4_200, randomValue: 0)
        #expect(resumed.pausedAt == nil)
        #expect(resumed.endsAt == 33_000)
        // The cue on screen was withdrawn unscored; a new wait starts.
        #expect(resumed.cueShownAt == nil && resumed.trials.isEmpty && resumed.falseStartCount == 0)
        #expect(resumed.nextCueAt == 5_200)
    }
}

@Suite("Reaction Test score")
struct VigilanceScoreTests {
    private func trials(_ reactions: [Double?]) -> [VigilanceTrial] {
        reactions.enumerated().map { VigilanceTrial(cueAt: Double($0.offset) * 3_000, reactionMs: $0.element) }
    }

    @Test func speedLedBands() {
        let sharp = Vigilance.score(trials: trials(Array(repeating: 280, count: 10)), falseStartCount: 0)
        #expect(sharp.score == 82 && sharp.rating == .sharp)
        let best = Vigilance.score(trials: trials(Array(repeating: 240, count: 10)), falseStartCount: 0)
        #expect(best.score == 100)
        let steady = Vigilance.score(trials: trials(Array(repeating: 310, count: 10)), falseStartCount: 0)
        #expect(steady.score == 67 && steady.rating == .steady)
        let slipping = Vigilance.score(trials: trials(Array(repeating: 360, count: 10)), falseStartCount: 0)
        #expect(slipping.score == 48 && slipping.rating == .slipping)
        let empty = Vigilance.score(trials: [], falseStartCount: 2)
        #expect(empty.score == 8 && empty.rating == .sluggish)
    }

    @Test func consistencyNoLongerCounts() {
        // Same mean 1/RT (3.33 per second), very different spread: same score.
        let even = Vigilance.score(trials: trials([300, 300, 300, 300]), falseStartCount: 0)
        let spread = Vigilance.score(trials: trials([250, 375, 250, 375]), falseStartCount: 0)
        #expect(abs(even.score - spread.score) <= 1)
    }

    @Test func meanReciprocalReactionTimeSeesSlowResponsesTheMedianWouldMiss() {
        let quick = Vigilance.buildSession(id: "a", startedAt: 0, completedAt: 30_000, trials: trials([270, 280, 290, 280, 280]), falseStarts: [])
        let oneSlow = Vigilance.buildSession(id: "b", startedAt: 0, completedAt: 30_000, trials: trials([270, 280, 290, 280, 390]), falseStarts: [])
        #expect(quick.medianReactionMs == oneSlow.medianReactionMs)
        #expect(oneSlow.score < quick.score)
    }

    @Test func lapsesCountButWeighLessThanBefore() {
        let clean = Vigilance.score(trials: trials(Array(repeating: 280, count: 10)), falseStartCount: 0)
        let oneMiss = Vigilance.score(trials: trials(Array(repeating: 280, count: 9) + [nil]), falseStartCount: 0)
        #expect(oneMiss.score == 69)
        #expect(clean.score - oneMiss.score == 13)
        let falseStart = Vigilance.score(trials: trials(Array(repeating: 280, count: 10)), falseStartCount: 1)
        #expect(falseStart.score == 81)
    }

    @Test func buildSessionCarriesTheProtocolAndTrials() {
        let run = trials([250, 99.5, 420, nil, 300])
        let falseStarts = [VigilanceFalseStart(at: 100), VigilanceFalseStart(at: 4_050, afterCueMs: 50)]
        let session = Vigilance.buildSession(id: "s", startedAt: 0, completedAt: 30_400, trials: run, falseStarts: falseStarts, deviceModel: "iPhone17,1")
        #expect(session.protocolVersion == 2 && session.protocolLabel == nil)
        #expect(session.trials == run && session.falseStarts == falseStarts && session.deviceModel == "iPhone17,1")
        #expect(session.trialCount == 5 && session.validReactionCount == 2 && session.lapseCount == 2 && session.falseStartCount == 2)
        #expect(session.medianReactionMs == 275 && session.fastestReactionMs == 250)
        // Re-scoring from the stored trials gives the same session.
        #expect(Vigilance.buildSession(id: "s", startedAt: 0, completedAt: 30_400, trials: session.trials, falseStarts: session.falseStarts, deviceModel: session.deviceModel) == session)
    }
}

@Suite("Reaction Test versions")
struct VigilanceProtocolTests {
    @Test func aStoredSessionWithoutAVersionIsTheEarlierTest() throws {
        let json = #"{"id":"v","startedAt":1000,"completedAt":61000,"durationMs":60000,"trialCount":14,"validReactionCount":13,"falseStartCount":0,"lapseCount":1,"medianReactionMs":301,"meanReactionMs":309,"fastestReactionMs":250,"reactionStdDevMs":40,"score":64,"rating":"Steady"}"#
        let session = try JSONDecoder().decode(VigilanceSession.self, from: Data(json.utf8))
        #expect(session.protocolVersion == 1)
        #expect(session.trials.isEmpty && session.falseStarts.isEmpty && session.deviceModel == nil)
        #expect(session.protocolLabel == "Earlier 60-second test")
    }

    @Test func theCurrentVersionRoundTrips() throws {
        let session = Vigilance.buildSession(
            id: "v2", startedAt: 0, completedAt: 30_000,
            trials: [VigilanceTrial(cueAt: 1_500, reactionMs: 286, cueLatencyMs: 9), VigilanceTrial(cueAt: 4_000, reactionMs: nil, cueLatencyMs: 4)],
            falseStarts: [VigilanceFalseStart(at: 900)], deviceModel: "iPad16,3"
        )
        let data = try JSONEncoder().encode(session)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["protocolVersion"] as? Int == 2)
        #expect(try JSONDecoder().decode(VigilanceSession.self, from: data) == session)
    }

    @Test func normalizationKeepsWhatTheAppWrites() {
        var session = Vigilance.buildSession(
            id: "v", startedAt: 0, completedAt: 30_000,
            trials: [VigilanceTrial(cueAt: 1_500, reactionMs: 286, cueLatencyMs: 9)], falseStarts: [VigilanceFalseStart(at: 900)],
            deviceModel: "iPhone17,1"
        )
        #expect(session.normalized() == session)
        session.protocolVersion = -4
        session.trials.append(VigilanceTrial(cueAt: 1e300, reactionMs: 300))
        session.trials.append(VigilanceTrial(cueAt: 2_000, reactionMs: -5, cueLatencyMs: .infinity))
        session.falseStarts.append(VigilanceFalseStart(at: .nan))
        session.falseStarts.append(VigilanceFalseStart(at: 3_000, afterCueMs: -.infinity))
        session.deviceModel = String(repeating: "x", count: 500)
        let cleaned = session.normalized()
        #expect(cleaned.protocolVersion == 1)
        #expect(cleaned.trials == [VigilanceTrial(cueAt: 1_500, reactionMs: 286, cueLatencyMs: 9), VigilanceTrial(cueAt: 2_000, reactionMs: nil)])
        #expect(cleaned.falseStarts == [VigilanceFalseStart(at: 900), VigilanceFalseStart(at: 3_000)])
        #expect(cleaned.deviceModel?.count == 64)
        #expect(cleaned.normalized() == cleaned)
        var empty = session
        empty.deviceModel = ""
        #expect(empty.normalized().deviceModel == nil)
    }

    @Test func loadingNormalizesStoredSessions() throws {
        var state = AppState()
        var session = Vigilance.buildSession(id: "v", startedAt: now - 30_000, completedAt: now, trials: [VigilanceTrial(cueAt: now - 20_000, reactionMs: 300)], falseStarts: [])
        session.trials.append(VigilanceTrial(cueAt: -1e300, reactionMs: 300))
        state.vigilanceSessions = [session]
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        let cleaned = decoded.droppingInvalidTimes()
        #expect(cleaned.vigilanceSessions.first?.trials.count == 1)
        #expect(cleaned.droppingInvalidTimes() == cleaned)
    }

    @Test func baselinesCompareOnlyTheSameVersion() {
        let day = dayMs
        let earlier = (1...4).map { session("old\($0)", completedAt: now - Double($0 + 1) * day, score: 60 + $0, protocolVersion: 1) }
        // Only old tests: the latest is labeled and its own version makes the baseline.
        let old = Insights.reactionSignal(sessions: earlier, now: now, clock: utc, text: fixtureText)
        #expect(old.baseline == .established && old.recentTests == 4)
        #expect(old.signal.context.hasPrefix("Earlier 60-second test · Steady · 280 ms median · Baseline") == true)
        // One new test starts a new baseline; the earlier tests don't count toward it.
        let current = session("new", completedAt: now - 1_000, score: 82, protocolVersion: 2)
        let mixed = Insights.reactionSignal(sessions: earlier + [current], now: now, clock: utc, text: fixtureText)
        #expect(mixed.baseline == .building && mixed.recentTests == 1)
        #expect(mixed.signal.value == "82")
        #expect(mixed.signal.context == "Sharp · 280 ms median · 1 of 3 tests toward a baseline (last 30 days)")
        let summary = SummarySignals.reactionTest(sessions: earlier, now: now, clock: utc, text: fixtureText)
        #expect(summary.context == "Earlier 60-second test · Steady · 280 ms median")
    }

    @Test func trendsPlotOnlyTheLatestVersion() {
        var state = AppState()
        state.vigilanceSessions = [
            session("old", completedAt: now - 2 * dayMs, score: 64, protocolVersion: 1),
            session("new", completedAt: now - 1_000, score: 82, protocolVersion: 2),
        ]
        let card = AssistantCards.make(.trends, state: state, now: now, clock: utc, text: fixtureText)
        let points = card.series.first { $0.metric == "Reaction" && $0.days == 7 }?.points ?? []
        #expect(points.compactMap(\.value) == [82])
        #expect(points.contains { $0.value == nil && $0.detail == "Earlier 60-second test · 64 · Steady" })
        let history = AssistantCards.make(.history, state: state, now: now, clock: utc, text: fixtureText)
        #expect(history.records.first { $0.id == "old" }?.detail == "Earlier 60-second test · 64 · Steady")
        #expect(history.records.first { $0.id == "new" }?.detail == "82 · Sharp")
        let snapshot = EnergySnapshot.capture(state: state, now: now, clock: utc, includeProjection: false)
        #expect(snapshot.reactions.map(\.title) == ["Reaction Test"])
    }

    @Test func exportHasAProtocolColumn() {
        let csv = Export.vigilanceSessionsCSV([
            session("old", completedAt: now - dayMs, score: 64, protocolVersion: 1),
            session("new", completedAt: now, score: 82, protocolVersion: 2),
        ])
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines[0].hasSuffix(",data_source,protocol"))
        #expect(lines[1].hasPrefix("\"old\",") && lines[1].hasSuffix(",\"Recorded\",\"1\""))
        #expect(lines[2].hasPrefix("\"new\",") && lines[2].hasSuffix(",\"Recorded\",\"2\""))
    }

    @Test func sampleTestsAreTheCurrentVersion() {
        let sample = SampleData.snapshot(now: now, clock: utc)
        #expect(sample.vigilanceSessions.count == 3)
        #expect(sample.vigilanceSessions.allSatisfy { $0.protocolVersion == Vigilance.protocolVersion && $0.trials.count == 10 && $0.durationMs == 30_000 })
        #expect(sample.vigilanceSessions.map(\.score) == [93, 77, 55])
        #expect(sample.vigilanceSessions.map(\.rating) == [.sharp, .steady, .slipping])
    }

    @Test func copyNamesThe30SecondTest() {
        let empty = AppState()
        let card = AssistantCards.make(.reaction, state: empty, now: now, clock: utc, text: fixtureText)
        #expect(card.summary == "A 30-second reaction test.")
        let signal = Insights.reactionSignal(sessions: [], now: now, clock: utc, text: fixtureText)
        #expect(signal.signal.context.contains("30-second"))
        #expect(SummarySignals.reactionTest(sessions: [], now: now, clock: utc, text: fixtureText).context == "A 30-second test of reaction speed.")
        for text in [card.summary, signal.signal.context] {
            #expect(!text.contains("PVT") && !text.contains("60-second"))
        }
    }
}
