import Foundation
import Testing
@testable import AuroraCore

/// Every case compares the Swift port with what the TypeScript original
/// produced for the same records, in UTC and in America/Los_Angeles (across
/// both 2026 DST changes).
@Suite("Parity with the TypeScript build")
struct ParityTests {
    struct Context {
        let clock: LocalClock
        let scenario: JSONValue
        let now: Millis
        let doses: [Dose]
        let sleeps: [SleepSession]
        let vigilance: [VigilanceSession]

        var inputs: EstimateInputs { EstimateInputs(halfLifeHours: 5, targetSleepHours: 8, clock: clock) }
    }

    static func contexts() throws -> [Context] {
        try Fixture.zones.flatMap { zone -> [Context] in
            let fixture = try Fixture.load("core-\(zone)")
            let identifier = try #require(fixture.text("zone"))
            let clock = LocalClock(timeZone: try #require(TimeZone(identifier: identifier)))
            return fixture.list("scenarios").map { scenario in
                let data = scenario["dataset"] ?? .null
                return Context(
                    clock: clock,
                    scenario: scenario,
                    now: scenario.double("now") ?? 0,
                    doses: data.list("doses").map(dose),
                    sleeps: data.list("sleeps").map(sleepSession),
                    vigilance: data.list("vigilance").map(vigilance)
                )
            }
        }
    }

    @Test func alertnessEstimates() throws {
        for context in try Self.contexts() {
            for probe in context.scenario.list("alertness") {
                let t = try #require(probe.double("t"))
                let estimate = Summary.estimateAlertness(at: t, doses: context.doses, sleeps: context.sleeps, inputs: context.inputs)
                let expected = probe["estimate"] ?? .null
                switch estimate {
                case .needsSleep:
                    #expect(expected.text("status") == "needs-sleep")
                case .estimated(let score, let hours, let sample):
                    #expect(expected.text("status") == "estimated")
                    #expect(score == expected.int("score"), "\(context.clock.timeZone.identifier) t=\(t)")
                    #expect(approxEqual(hours, expected.double("sleepHours")))
                    #expect(sample == expected.flag("includesSample"))
                }
                #expect(Summary.describe(estimate) == probe.text("text"))
            }
        }
    }

    @Test func cutoffAnnotations() throws {
        for context in try Self.contexts() {
            for item in context.scenario.list("cutoff") {
                let hour = try #require(item.double("cutoffHour"))
                for (key, doses) in [("withDoses", context.doses), ("withoutDoses", [Dose]())] {
                    let annotation = Summary.cutoffAnnotation(
                        now: context.now, cutoffHour: hour, doses: doses, clock: context.clock, formatTime: fixtureTime
                    )
                    let expected = item[key] ?? .null
                    if expected.isNull {
                        #expect(annotation == nil, "\(context.clock.timeZone.identifier) \(hour) \(key)")
                    } else {
                        #expect(annotation?.at == expected.double("at"))
                        #expect(annotation?.isPast == expected.flag("isPast"))
                        #expect(annotation?.nextAt == expected.double("nextAt"), "\(context.clock.timeZone.identifier) now=\(context.now) h=\(hour)")
                        #expect(annotation?.text == expected.text("text"))
                    }
                }
            }
        }
    }

    @Test func caffeineDayDescription() throws {
        for context in try Self.contexts() {
            let dayStart = context.clock.startOfDay(context.now)
            let series = (0..<25).map { CaffeinePoint(t: dayStart + Double($0) * hourMs, mg: Double(($0 * 7) % 30)) }
            let expected = context.scenario["caffeineDay"] ?? .null
            #expect(Summary.describeCaffeineDay(
                series: series, doses: context.doses, dayStart: dayStart, dayEnd: dayStart + dayMs, formatTime: fixtureTime
            ) == expected.text("text"))
            #expect(Summary.hasCaffeineSignal(series: series, doses: context.doses, dayStart: dayStart, dayEnd: dayStart + dayMs) == expected.flag("has"))
        }
    }

    @Test func sleepPresentations() throws {
        for context in try Self.contexts() {
            for (key, range, target) in [("sleepWeek", SleepRange.week, 8.0), ("sleepMonth", SleepRange.month, 7.5)] {
                let p = SleepModel.presentation(
                    sessions: context.sleeps, targetSleepHours: target, range: range, now: context.now, clock: context.clock, text: fixtureText
                )
                let expected = context.scenario[key] ?? .null
                let points = expected.list("points")
                #expect(p.points.count == points.count)
                for (point, want) in zip(p.points, points) {
                    #expect(point.date == want.double("date"), "\(context.clock.timeZone.identifier) \(key)")
                    #expect(point.durationMs == want.double("durationMs"), "\(context.clock.timeZone.identifier) \(key) day \(point.date)")
                }
                #expect(p.recordedNights == expected.int("recordedNights"))
                #expect(approxEqual(p.averageDurationMs, expected.double("averageDurationMs")))
                #expect(p.headline == expected.text("headline"))
                let last = expected["lastNight"] ?? .null
                if last.isNull {
                    #expect(p.lastNight == nil)
                } else {
                    let night = try #require(p.lastNight)
                    #expect(night.session.id == last["session"]?.text("id"))
                    #expect(night.sessionIDs == last.list("sessionIds").compactMap(\.string))
                    #expect(night.durationMs == last.double("durationMs"))
                    #expect(night.sleepStart == last.double("sleepStart"))
                    #expect(night.wakeTime == last.double("wakeTime"))
                    #expect(night.targetDifferenceMs == last.double("targetDifferenceMs"))
                }
            }
        }
    }

    @Test func caffeineTiming() throws {
        for context in try Self.contexts() {
            for (key, range) in [("impactWeek", SleepRange.week), ("impactMonth", SleepRange.month)] {
                let impact = SleepModel.caffeineImpact(sessions: context.sleeps, doses: context.doses, range: range, now: context.now, clock: context.clock)
                let expected = context.scenario[key] ?? .null
                #expect(impact.qualifyingNights == expected.int("qualifyingNights"), "\(context.clock.timeZone.identifier) \(key)")
                #expect(impact.medianDeltaMin == expected.int("medianDeltaMin"))
                #expect(impact.p10 == expected.int("p10"))
                #expect(impact.p90 == expected.int("p90"))
                #expect(impact.medianSleepMin == expected.int("medianSleepMin"))
                #expect(impact.meetsPairedNightGate == expected.flag("meetsPairedNightGate"))
            }
            for (key, sleeps) in [("timing", context.sleeps), ("timingFew", Array(context.sleeps.prefix(3)))] {
                let signal = SleepModel.caffeineTimingSignal(sleeps: sleeps, doses: context.doses, now: context.now, clock: context.clock)
                let expected = context.scenario[key] ?? .null
                switch signal {
                case .gathering(let paired, let required, let text):
                    #expect(expected.text("status") == "gathering")
                    #expect(paired == expected.int("pairedNights"))
                    #expect(required == expected.int("required"))
                    #expect(text == expected.text("text"))
                case .observed(let paired, let period, let value, let contextLine, let rows, let label):
                    #expect(expected.text("status") == "observed")
                    #expect(paired == expected.int("pairedNights"))
                    #expect(period == expected.text("period"))
                    #expect(value == expected.text("value"))
                    #expect(contextLine == expected.text("context"))
                    #expect(rows.map(\.value) == expected.list("detailRows").compactMap { $0.text("value") })
                    #expect(label == expected.text("accessibilityLabel"))
                }
            }
        }
    }

    @Test func signals() throws {
        for context in try Self.contexts() {
            let s = context.scenario
            expectSignal(
                SleepModel.recentNightSignal(sleeps: context.sleeps, targetSleepHours: 8, now: context.now, clock: context.clock, text: fixtureText),
                s["recentNight"] ?? .null
            )
            expectSignal(
                SleepModel.recentNightSignal(sleeps: [], targetSleepHours: 8, now: context.now, clock: context.clock, text: fixtureText),
                s["recentNightEmpty"] ?? .null
            )
            #expect(SleepModel.episodeSourceLabel(ids: ["demo:sleep:1", "manual:sleep:x", "healthkit:sleep:1:2"]) == s.text("episodeSources"))
            expectSignal(
                SummarySignals.caffeineLogged(doses: context.doses, now: context.now, clock: context.clock, formatTime: fixtureTime),
                s["caffeineSignal"] ?? .null
            )
            expectSignal(
                SummarySignals.caffeineLogged(
                    doses: context.doses.filter { !RecordID.isSample($0.id) }, now: context.now, clock: context.clock, formatTime: fixtureTime
                ),
                s["caffeineSignalManual"] ?? .null
            )
            expectSignal(
                SummarySignals.sleep(sleeps: context.sleeps, targetSleepHours: 8, now: context.now, clock: context.clock, text: fixtureText),
                s["sleepSignal"] ?? .null
            )
            expectSignal(
                SummarySignals.reactionTest(sessions: context.vigilance, now: context.now, clock: context.clock, text: fixtureText),
                s["reactionSignal"] ?? .null
            )
            let logged = CaffeineLog.loggedToday(context.doses, now: context.now, clock: context.clock, formatTime: fixtureTime)
            let expected = s["loggedToday"] ?? .null
            #expect(logged.value == expected.text("value"))
            #expect(logged.source == expected.text("source"))
            #expect(logged.sample == expected.flag("sample"))
            #expect(logged.detail == expected.text("detail"))
            #expect(logged.accessibilityLabel == expected.text("accessibilityLabel"))
            #expect(CaffeineLog.recent(context.doses).map(\.id) == s.list("recent").compactMap(\.string))
        }
    }

    @Test func insights() throws {
        for context in try Self.contexts() {
            for expected in context.scenario.list("insights") {
                let range = try #require(InsightsRange(rawValue: Int(expected.text("range") ?? "") ?? 0))
                let p = Insights.presentation(
                    doses: context.doses, vigilanceSessions: context.vigilance, range: range, now: context.now, clock: context.clock, text: fixtureText
                )
                let label = "\(context.clock.timeZone.identifier) \(range.days)"
                let points = expected.list("points")
                #expect(p.points.count == points.count)
                for (point, want) in zip(p.points, points) {
                    #expect(point.date == want.double("date"), "\(label)")
                    #expect(point.mg.map(Double.init) == want.double("mg"), "\(label) \(point.date)")
                    #expect(point.entries == want.int("entries"))
                    #expect(point.source?.rawValue == want.text("source"))
                }
                #expect(p.recordedDays == expected.int("recordedDays"), "\(label)")
                #expect(p.missingDays == expected.int("missingDays"))
                #expect(p.headline == expected.text("headline"))
                #expect(p.source?.rawValue == expected.text("source"))
                #expect(p.trend.text == expected["trend"]?.text("text"), "\(label)")
                if case .compared(let direction, _, _, _, _, let detail) = p.trend {
                    #expect(direction.rawValue == expected["trend"]?.text("direction"))
                    #expect(detail == expected["trend"]?.text("detail"))
                }
                #expect(p.dayparts.map(\.label) == expected.list("dayparts").compactMap { $0.text("label") })
                #expect(p.dayparts.map(\.mg) == expected.list("dayparts").compactMap { $0.double("mg") }, "\(label)")
                #expect(p.dayparts.map(\.entries) == expected.list("dayparts").compactMap { $0.int("entries") })
                #expect(p.drinkMix.map(\.label) == expected.list("drinkMix").compactMap { $0.text("label") }, "\(label)")
                #expect(p.drinkMix.map(\.mg) == expected.list("drinkMix").compactMap { $0.double("mg") })
                #expect(p.drinkMix.map(\.pct) == expected.list("drinkMix").compactMap { $0.int("pct") })
                let reaction = expected["reaction"] ?? .null
                expectSignal(p.reaction.signal, reaction)
                #expect(p.reaction.baseline.rawValue == reaction.text("baseline"))
                #expect(p.reaction.recentTests == reaction.int("recentTests"))
                #expect(p.latestRecordedIndex == expected.int("latestRecordedIndex"))
                #expect(p.isEmpty == expected.flag("isEmpty"))
                #expect(p.previous.recordedDays == expected.int("previousRecordedDays"), "\(label)")
                #expect(p.previous.averageMg.map(Double.init) == expected.double("previousAverage"))
            }
        }
    }

    @Test func exports() throws {
        for context in try Self.contexts() {
            let expected = context.scenario["export"] ?? .null
            let rows = Export.dailyTotalRows(context.doses, now: context.now, clock: context.clock)
            let wantRows = expected.list("dailyRows")
            #expect(rows.count == wantRows.count, "\(context.clock.timeZone.identifier)")
            for (row, want) in zip(rows, wantRows) {
                #expect(row.date == want.text("date"))
                #expect(row.mg.map(Double.init) == want.double("mg"))
                #expect(row.entries == want.int("entries"))
                #expect(row.source == want.text("source"))
            }
            #expect(Export.dailyTotalsCSV(rows) == expected.text("dailyCSV"))
            #expect(Export.doseEntriesCSV(context.doses, clock: context.clock) == expected.text("doseCSV"))
            #expect(Export.vigilanceSessionsCSV(context.vigilance) == expected.text("vigilanceCSV"))
        }
    }

    @Test func vigilanceScoring() throws {
        let fixture = try Fixture.load("core-UTC")
        let cases: [[VigilanceTrialResult]] = [
            [.valid(reactionMs: 240), .valid(reactionMs: 301), .lapse(reactionMs: nil)],
            [.valid(reactionMs: 220), .valid(reactionMs: 260)],
            [],
            [.lapse(reactionMs: 640), .valid(reactionMs: 333), .valid(reactionMs: 287), .valid(reactionMs: 412)],
        ]
        let expected = fixture.list("vigilance")
        #expect(expected.count == cases.count)
        for (index, (trials, want)) in zip(cases, expected).enumerated() {
            let session = Vigilance.buildSession(
                id: "case-\(index)", startedAt: 1_000, completedAt: Double(61_000 + index), trialResults: trials, falseStartCount: index
            )
            #expect(session == vigilance(want["session"] ?? .null), "case \(index)")
        }
    }

    @Test func legacyMigration() throws {
        let fixture = try Fixture.load("legacy")
        let now = try #require(fixture.double("now"))
        guard case .object(let cases) = fixture["cases"] ?? .null else {
            Issue.record("missing cases")
            return
        }
        for (name, item) in cases {
            let state = try LegacyState.decode(try #require(item.text("raw")), now: now)
            let want = item["state"] ?? .null
            #expect(state.doses == want.list("doses").map(dose), "\(name)")
            #expect(state.sleeps == want.list("sleeps").map(sleepSession), "\(name)")
            #expect(state.vigilanceSessions.map(\.id) == want.list("vigilanceSessions").compactMap { $0.text("id") })
            #expect(state.vigilanceSessions.map(\.rating.rawValue) == want.list("vigilanceSessions").compactMap { $0.text("rating") }, "\(name)")
            let prefs = want["prefs"] ?? .null
            #expect(state.prefs.halfLife == prefs.double("halfLife"))
            #expect(state.prefs.targetSleep == prefs.double("targetSleep"))
            #expect(state.prefs.dailyLimitMg == prefs.double("dailyLimitMg"))
            #expect(state.prefs.cutoffHour == prefs.double("cutoffHour"))
            #expect(state.prefs.notifyCutoff == prefs.flag("notifyCutoff"))
            #expect(state.prefs.tz == prefs.text("tz"))
            let onboarding = want["onboarding"] ?? .null
            #expect(state.onboarding.completed == onboarding.flag("completed"), "\(name)")
            #expect(state.onboarding.source.rawValue == onboarding.text("source"))
            #expect(state.onboarding.permissionStatus.rawValue == onboarding.text("permissionStatus"))
            #expect(state.onboarding.appWalkthroughCompleted == onboarding.flag("appWalkthroughCompleted"), "\(name)")
            #expect(state.onboarding.appWalkthroughStep == onboarding.int("appWalkthroughStep"), "\(name)")
            let sync = want["healthSync"] ?? .null
            #expect(state.healthSync.importStatus.rawValue == sync.text("importStatus"), "\(name)")
            #expect(state.healthSync.importedCount == sync.int("importedCount"))
            #expect(state.healthSync.lastMessage == sync.text("lastMessage"), "\(name)")
            #expect(state.demoMode == want.flag("demoMode"))
            #expect(state.appearanceMode.rawValue == want.text("appearanceMode"))
        }
    }
}
