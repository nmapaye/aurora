import Foundation
import Testing
@testable import AuroraCore

private let utc = LocalClock(timeZone: TimeZone(identifier: "UTC")!)
private let pacific = LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
private let now: Millis = 1_790_527_260_000 // 2026-09-27 16:41 UTC

@Suite struct StoreTests {
    @Test func doseCorrectionKeepsID() {
        var state = AppState()
        state.addDose(Dose(id: "a", timestamp: 1, mg: 95, source: "Drip", note: "x"))
        state.updateDose(id: "a", timestamp: 2, mg: 60, source: nil, note: nil)
        #expect(state.doses == [Dose(id: "a", timestamp: 2, mg: 60)])
        state.removeDose(id: "a")
        #expect(state.doses.isEmpty)
    }

    @Test func onlyManualSleepIsEditable() {
        var state = AppState()
        state.sleeps = [
            SleepSession(id: "manual:sleep:1:a", start: 0, end: 10),
            SleepSession(id: "healthkit:sleep:0:10", start: 0, end: 10),
            SleepSession(id: "demo:sleep:0", start: 0, end: 10),
        ]
        for session in state.sleeps {
            state.updateManualSleep(id: session.id, end: 20)
            state.removeManualSleep(id: session.id)
        }
        #expect(state.sleeps.map(\.id) == ["healthkit:sleep:0:10", "demo:sleep:0"])
        #expect(state.sleeps.allSatisfy { $0.end == 10 })
    }

    @Test func healthWindowReplacementLeavesOtherSleep() {
        var state = AppState()
        let day = dayMs
        state.sleeps = [
            SleepSession(id: HealthSleepIdentity.id(start: now - 2 * day, end: now - 2 * day + hourMs), start: now - 2 * day, end: now - 2 * day + hourMs),
            SleepSession(id: HealthSleepIdentity.id(start: now - 40 * day, end: now - 40 * day + hourMs), start: now - 40 * day, end: now - 40 * day + hourMs),
            SleepSession(id: "manual:sleep:1:a", start: now - day, end: now - day + hourMs),
        ]
        state.replaceHealthSleepWindow([], windowStart: now - 30 * day, windowEnd: now, now: now)
        #expect(state.sleeps.map(\.id) == ["manual:sleep:1:a", HealthSleepIdentity.id(start: now - 40 * day, end: now - 40 * day + hourMs)])
    }

    @Test func upsertDedupesHealthSleepAndTrimsOldHealth() {
        var state = AppState()
        let old = SleepSession(id: "healthkit:sleep:1:2", start: 1, end: 2)
        let fresh = SleepSession(id: "x", start: now - hourMs, end: now)
        state.upsertSleepSessions([old, fresh, fresh], now: now)
        #expect(state.sleeps == [fresh])
    }

    @Test func sampleDataLoadsAndClears() {
        var state = AppState()
        state.addDose(Dose(id: "mine", timestamp: now, mg: 50))
        state.loadSampleData(now: now, clock: pacific)
        #expect(state.demoMode)
        #expect(state.onboarding.completed)
        #expect(state.onboarding.source == .manual)
        #expect(state.doses.count == 17)
        #expect(state.doses.map(\.timestamp) == state.doses.map(\.timestamp).sorted(by: >))
        state.loadSampleData(now: now, clock: pacific)
        #expect(state.doses.count == 17)
        state.clearSampleData()
        #expect(state.doses.map(\.id) == ["mine"])
        #expect(state.sleeps.isEmpty && state.vigilanceSessions.isEmpty && !state.demoMode)
    }

    @Test func deleteAllKeepsSettings() {
        var state = AppState()
        state.prefs.cutoffHour = 13
        state.appearanceMode = .dark
        state.completeOnboarding(now: now)
        state.loadSampleData(now: now, clock: utc)
        state.healthSync.importedCount = 3
        state.deleteAllData()
        #expect(state.doses.isEmpty && state.sleeps.isEmpty && state.vigilanceSessions.isEmpty)
        #expect(state.healthSync == .defaults)
        #expect(state.prefs.cutoffHour == 13 && state.appearanceMode == .dark && state.onboarding.completed)
    }

    @Test func walkthroughStepClamps() {
        var state = AppState()
        state.completeOnboarding(now: now)
        #expect(state.isWalkthroughPending)
        for _ in 0..<20 { state.advanceWalkthrough() }
        #expect(state.onboarding.appWalkthroughStep == 9)
        state.completeWalkthrough()
        #expect(!state.isWalkthroughPending)
    }

    @Test func stateRoundTripsThroughJSON() throws {
        var state = AppState()
        state.loadSampleData(now: now, clock: utc)
        state.prefs.tz = "Europe/Paris"
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
        #expect(try JSONDecoder().decode(AppState.self, from: Data("{}".utf8)) == AppState())
    }
}

@Suite struct MigrationTests {
    @Test(arguments: [1, 2])
    func mmkvReaderFindsTheStore(prefixes: Int) throws {
        let blob = #"{"state":{"doses":[{"id":"a","timestamp":1,"mg":95}]},"version":6}"#
        let data = MMKVReader.encode([
            (key: "aurora/state", value: "{\"state\":{},\"version\":6}"),
            (key: "other", value: "x"),
            (key: "aurora/state", value: blob),
        ], valuePrefixes: prefixes)
        let reader = try MMKVReader(data: data)
        let raw = try #require(reader.string(forKey: "aurora/state"))
        #expect(raw == blob)
        let state = try LegacyState.decode(raw, now: now)
        #expect(state.doses == [Dose(id: "a", timestamp: 1, mg: 95)])
    }

    @Test func mmkvRawJSONWhoseFirstByteLooksLikeALength() throws {
        // `{` is 123, so a raw 124-byte JSON value also parses as a
        // length-prefixed 123-byte value. The JSON reading must win.
        var blob = #"{"state":{"prefs":{"halfLife":0.5,"targetSleep":10,"dailyLimitMg":1000}},"version":1,"pad":""}"#
        while blob.utf8.count < 124 { blob.insert("x", at: blob.index(blob.endIndex, offsetBy: -2)) }
        #expect(blob.utf8.count == 124)
        let raw = MMKVReader.encode([(key: "aurora/state", value: blob)], valuePrefixes: 0)
        #expect(try MMKVReader(data: raw).string(forKey: "aurora/state") == blob)
        let state = try LegacyState.decode(blob, now: now)
        #expect(state.prefs.halfLife == 0.5)
    }

    @Test func mmkvPrefixedValueWhoseLengthIs123() throws {
        // The single-prefixed form of a 123-byte JSON value starts with
        // byte 123 too; here the unwrapped value is the JSON.
        var blob = #"{"state":{},"version":6,"pad":""}"#
        while blob.utf8.count < 123 { blob.insert("x", at: blob.index(blob.endIndex, offsetBy: -2)) }
        let data = MMKVReader.encode([(key: "aurora/state", value: blob)], valuePrefixes: 1)
        #expect(try MMKVReader(data: data).string(forKey: "aurora/state") == blob)
    }

    @Test func mmkvEmptyValueDeletesKey() throws {
        let data = MMKVReader.encode([(key: "k", value: "v"), (key: "k", value: "")], valuePrefixes: 0)
        #expect(try MMKVReader(data: data).string(forKey: "k") == nil)
    }

    @Test func mmkvRejectsTruncatedFiles() {
        #expect(throws: MMKVReader.Failure.self) { try MMKVReader(data: Data([1, 2])) }
        #expect(throws: MMKVReader.Failure.self) { try MMKVReader(data: Data([200, 0, 0, 0, 1])) }
    }

    @Test func unreadableBlobThrows() {
        #expect(throws: LegacyState.Failure.self) { try LegacyState.decode("{not json", now: now) }
    }

    @Test func legacyHealthIDsNormalize() {
        let legacy = SleepSession(id: "sleep:1000:2000", start: 1000, end: 2000)
        #expect(HealthSleepIdentity.normalize(legacy).id == "healthkit:sleep:1000:2000")
        let mismatched = SleepSession(id: "sleep:1000:2001", start: 1000, end: 2000)
        #expect(HealthSleepIdentity.normalize(mismatched).id == "sleep:1000:2001")
        #expect(HealthSleepIdentity.id(start: 10.5, end: -2.5) == "healthkit:sleep:11:-2")
    }
}

@Suite struct RuleTests {
    @Test func jsRoundingMatchesJavaScript() {
        #expect(jsRound(2.5) == 3)
        #expect(jsRound(-2.5) == -2)
        #expect(jsRound(-2.6) == -3)
    }

    @Test func quickAddIgnoresDoubleTaps() {
        #expect(CaffeineLog.acceptsQuickAdd(lastAcceptedAt: nil, at: 0))
        #expect(!CaffeineLog.acceptsQuickAdd(lastAcceptedAt: 1000, at: 1999))
        #expect(CaffeineLog.acceptsQuickAdd(lastAcceptedAt: 1000, at: 2000))
        #expect(CaffeineLog.acceptsQuickAdd(lastAcceptedAt: 1000, at: 500))
    }

    @Test func customEntryValidation() {
        func check(_ mg: String, _ ts: Millis = now) -> String? {
            CaffeineLog.validate(CustomDoseDraft(mg: mg, source: "", timestamp: ts, note: ""), now: now).message
        }
        #expect(check("80") == nil)
        #expect(check(" 1999 ") == nil)
        #expect(check("0") != nil)
        #expect(check("2000") != nil)
        #expect(check("12.5") != nil)
        #expect(check("") != nil)
        #expect(check("abc") != nil)
        #expect(check("80", now + 1) == "Time cannot be in the future.")
    }

    @Test func manualSleepValidation() {
        #expect(ManualSleep.validate(start: 0, end: 10, now: 20) == .valid)
        #expect(ManualSleep.validate(start: 10, end: 10, now: 20).message == "Start time must be before end time.")
        #expect(ManualSleep.validate(start: 0, end: 25 * hourMs, now: 30 * hourMs).message == "Sleep duration cannot exceed 24 hours.")
        #expect(ManualSleep.validate(start: 0, end: 30, now: 20).message == "End time cannot be in the future.")
    }

    @Test func sampleEntriesAreReadOnly() {
        let sample = Dose(id: "demo:dose:1", timestamp: 0, mg: 95, note: "Sample data")
        #expect(!CaffeineLog.isEditable(sample))
        #expect(CaffeineLog.displayNote(sample) == nil)
        #expect(CaffeineLog.describe(sample, formatDateTime: { _ in "when" }) == "95 mg, when, Sample Data, read-only")
        #expect(CaffeineLog.isEditable(Dose(id: "abc-1", timestamp: 0, mg: 1)))
    }

    @Test func noPrescriptiveCopy() {
        #expect(CopyRules.violations(in: "You have 120 mg remaining today.").isEmpty == false)
        #expect(CopyRules.violations(in: "Suggested bedtime: 10 PM").isEmpty == false)
        #expect(CopyRules.violations(in: "Personal caffeine reference. It is not a recommended or safe amount.").isEmpty)
        let texts = Walkthrough.steps.flatMap { [$0.title, $0.body] } +
            (0..<3).flatMap { step in
                [OnboardingSource.healthkit, .manual].flatMap { source -> [String] in
                    let copy = OnboardingCopy.stepCopy(step: step, source: source)
                    return [copy.eyebrow, copy.title, copy.body]
                }
            } +
            [Summary.noCaffeineBody, HealthImport.noSleepMessage]
        for text in texts {
            #expect(CopyRules.violations(in: text).isEmpty, "\(text)")
        }
    }

    @Test func todaySeriesCoversTheLocalDayAndNow() {
        let doses = [Dose(id: "a", timestamp: pacific.startOfDay(now) + 8 * hourMs, mg: 100)]
        let series = TodayCaffeineSeries.make(doses: doses, halfLifeHours: 5, now: now, clock: pacific)
        #expect(series.start == pacific.startOfDay(now))
        #expect(series.end == pacific.addingDays(1, to: series.start))
        #expect(series.series.count == 26)
        #expect(series.series.map(\.t) == series.series.map(\.t).sorted())
        #expect(series.series.contains { $0.t == now })
        #expect(series.series[8].hasDose)
    }

    @Test func storedTimeZoneSetsTheCircadianTerm() {
        var prefs = Prefs.defaults
        prefs.tz = "Asia/Tokyo"
        let inputs = EstimateInputs(prefs: prefs, clock: utc)
        #expect(inputs.clock.timeZone.identifier == "Asia/Tokyo")
        prefs.tz = "Not/AZone"
        #expect(EstimateInputs(prefs: prefs, clock: utc).clock.timeZone == utc.timeZone)
        prefs.tz = nil
        #expect(EstimateInputs(prefs: prefs, clock: pacific).clock.timeZone == pacific.timeZone)
    }

    @Test func cutoffRollsOverOnDSTChange() throws {
        // 2026-11-01: Pacific clocks fall back at 2 AM.
        let afternoon: Millis = 1_793_491_200_000 // Oct 31 17:00 PDT
        let dose = Dose(id: "a", timestamp: afternoon - hourMs, mg: 60)
        let annotation = try #require(Summary.cutoffAnnotation(
            now: afternoon, cutoffHour: 16, doses: [dose], clock: pacific, formatTime: { "\($0)" }
        ))
        #expect(annotation.isPast)
        #expect(pacific.hour(annotation.nextAt) == 16)
        #expect(annotation.nextAt - annotation.at == 25 * hourMs)
    }
}

@Suite struct NavigationTests {
    @Test(arguments: [
        ("aurora://summary", DeepLink.tab(.summary)),
        ("aurora://sleep?x=1", .tab(.sleep)),
        ("aurora://log#top", .tab(.log)),
        ("aurora://insights", .tab(.insights)),
        ("aurora://vigilance", .reactionTest),
        ("aurora://settings", .settings),
        ("aurora://sleep/history", .sleepHistory),
        ("com.nmapaye.aurora://caffeine/history", .caffeineHistory),
    ])
    func deepLinks(url: String, expected: DeepLink) throws {
        #expect(DeepLink(url: try #require(URL(string: url))) == expected)
    }

    @Test func unknownLinksAreIgnored() throws {
        #expect(DeepLink(url: try #require(URL(string: "aurora://nowhere"))) == nil)
        #expect(DeepLink(url: try #require(URL(string: "https://summary"))) == nil)
    }

    @Test func pendingWalkthroughRedirectsLinks() {
        #expect(DeepLink.settings.resolved(walkthroughPending: true, step: 6) == .tab(.log))
        #expect(DeepLink.settings.resolved(walkthroughPending: false, step: 6) == .settings)
    }

    @Test func walkthroughReducer() {
        var state = Walkthrough.State()
        state = Walkthrough.reduce(state, .next)
        #expect(state == Walkthrough.State())
        state = Walkthrough.reduce(state, .start)
        state = Walkthrough.reduce(state, .positioned)
        state = Walkthrough.reduce(state, .settled)
        #expect(state.phase == .coaching)
        state = Walkthrough.reduce(state, .finish)
        #expect(state.phase == .coaching)
        state = Walkthrough.reduce(state, .next)
        #expect(state == Walkthrough.State(stepIndex: 1, phase: .positioning))
        state = Walkthrough.reduce(state, .skip)
        #expect(state.phase == .complete)
        #expect(Walkthrough.revealedGroups(step: 1) == ["summary-header", "summary-today", "summary-alert", "summary-pinned"])
        #expect(Walkthrough.revealedGroups(step: 5) == ["sleep-header", "sleep-history", "sleep-data"])
        #expect(Walkthrough.steps.count == 10 && Walkthrough.steps.last?.isLast == true)
    }
}

@Suite struct SleepDataStatusTests {
    private func describe(_ change: (inout AppState) -> Void, available: Bool = true, error: String? = nil) -> SleepDataStatus.Description {
        var state = AppState()
        change(&state)
        return SleepDataStatus.describe(
            onboarding: state.onboarding, healthSync: state.healthSync, demoMode: state.demoMode,
            healthAvailable: available, refreshError: error
        )
    }

    @Test func statesInPriorityOrder() {
        #expect(describe({ $0.demoMode = true }, error: "boom") == .init(state: "Health refresh failed", detail: "Health refresh failed. boom"))
        #expect(describe({ $0.demoMode = true }).state == "Sample Data")
        #expect(describe({ _ in }, available: false).state == "Health unavailable")
        #expect(describe({ $0.onboarding.source = .manual; $0.onboarding.permissionStatus = .unsupported }).state == "Manual mode")
        #expect(describe({ $0.onboarding.permissionStatus = .denied }).state == "Health not connected")
        #expect(describe({ $0.onboarding.permissionStatus = .granted }).state == "Health access requested")
        let none = describe {
            $0.onboarding.permissionStatus = .granted
            $0.healthSync.importStatus = .succeeded
        }
        #expect(none.state == "No sleep found")
        #expect(none.detail.hasPrefix("Check sleep records"))
    }
}

/// Regressions for the risky paths named in the pre-review audit.
@Suite struct PreflightTests {
    @Test func sampleDosesIgnoreEditsAndDeletes() {
        var state = AppState()
        state.loadSampleData(now: now, clock: utc)
        guard let sample = state.doses.first else {
            Issue.record("no sample doses")
            return
        }
        state.updateDose(id: sample.id, timestamp: 1, mg: 1, source: nil, note: nil)
        state.removeDose(id: sample.id)
        #expect(state.doses.first == sample)
        #expect(!CaffeineLog.isEditable(sample))
    }

    @Test func sampleSleepAndReactionTestsStayPut() {
        var state = AppState()
        state.loadSampleData(now: now, clock: utc)
        let sleeps = state.sleeps
        let sessions = state.vigilanceSessions
        #expect(!sleeps.isEmpty && !sessions.isEmpty)
        for sleep in sleeps {
            state.updateManualSleep(id: sleep.id, start: 0, end: 1, note: "x")
            state.removeManualSleep(id: sleep.id)
        }
        #expect(state.sleeps == sleeps)
        #expect(state.vigilanceSessions == sessions)
    }

    @Test func legacySleepIDsAreReadOnly() {
        // An old Health ID that does not match its own boundaries keeps its
        // id and is not manual, so it cannot be changed.
        var state = AppState()
        state.sleeps = HealthSleepIdentity.normalize([SleepSession(id: "sleep:1:2", start: 100, end: 200)])
        let before = state.sleeps
        for sleep in before {
            state.updateManualSleep(id: sleep.id, end: 300)
            state.removeManualSleep(id: sleep.id)
        }
        #expect(state.sleeps == before)
        #expect(before.allSatisfy { !RecordID.isManualSleep($0.id) })
    }

    @Test func overlappingManualAndHealthSleepCountsOnce() {
        // Health 23:00-07:00 and a manual 01:00-05:00 entry for the same night.
        let wake = utc.startOfDay(now) + 7 * hourMs
        let sessions = [
            SleepSession(id: HealthSleepIdentity.id(start: wake - 8 * hourMs, end: wake), start: wake - 8 * hourMs, end: wake),
            SleepSession(id: "manual:sleep:1:a", start: wake - 6 * hourMs, end: wake - 2 * hourMs),
        ]
        let week = SleepModel.presentation(sessions: sessions, targetSleepHours: 8, range: .week, now: now, clock: utc, text: fixtureText)
        #expect(week.points.last?.durationMs == 8 * hourMs)
        #expect(week.recordedNights == 1)
    }

    @Test func daysWithoutSleepAreMissingNotZero() {
        let wake = utc.startOfDay(now) + 7 * hourMs
        let sessions = [SleepSession(id: "manual:sleep:1:a", start: wake - 6 * hourMs, end: wake)]
        let week = SleepModel.presentation(sessions: sessions, targetSleepHours: 8, range: .week, now: now, clock: utc, text: fixtureText)
        #expect(week.points.count == 7)
        #expect(week.points.dropLast().allSatisfy { $0.durationMs == nil })
        #expect(week.averageDurationMs == 6 * hourMs)
    }

    @Test func manualSleepAcrossDSTUsesElapsedTime() {
        // US DST ends Nov 1 2026 at 02:00 PDT; 23:00 to 07:00 local is nine hours.
        let start = localMillis(pacific, 2026, 10, 31, 23)
        let end = localMillis(pacific, 2026, 11, 1, 7)
        let sessions = [SleepSession(id: "manual:sleep:1:a", start: start, end: end)]
        let week = SleepModel.presentation(sessions: sessions, targetSleepHours: 8, range: .week, now: end + hourMs, clock: pacific, text: fixtureText)
        #expect(week.points.last?.durationMs == 9 * hourMs)
    }
}

private func localMillis(_ clock: LocalClock, _ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Millis {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = clock.timeZone
    let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    return date.timeIntervalSince1970 * 1000
}

/// Regressions for the core review's findings.
@Suite struct ReviewFindingTests {
    @Test(arguments: [1e300, -1e300, 9.3e18, -9.3e18, Double(Int.max), -Double(Int.max), Double.greatestFiniteMagnitude, 0x1p63 - 1024])
    func roundingHugeNumbersSaturates(value: Double) {
        let rounded = jsRoundInt(value)
        if value >= 0x1p63 { #expect(rounded == .max) }
        if value <= -0x1p63 { #expect(rounded == .min) }
        if abs(value) < 0x1p63 { #expect(Double(rounded) == jsRound(value)) }
        #expect(saturatingInt(.nan) == 0)
    }

    /// A store an old build, or a hand edit, could leave: every number finite
    /// but far outside what the app ever writes.
    static let hugeBlob = """
    {"version":6,"state":{
      "doses":[
        {"id":"big","timestamp":1790520000000,"mg":1e300,"source":"Drip"},
        {"id":"big2","timestamp":1790520060000,"mg":1.7976931348623157e308},
        {"id":"far","timestamp":1e300,"mg":95},
        {"id":"past","timestamp":-1e300,"mg":95},
        {"id":"edge","timestamp":8.64e15,"mg":95},
        {"id":"ancient","timestamp":-8.64e15,"mg":50}
      ],
      "sleeps":[
        {"id":"manual:sleep:1:a","start":-1e300,"end":1e300,"type":"sleep"},
        {"id":"manual:sleep:2:b","start":1790490000000,"end":1790518800000,"type":"sleep"}
      ],
      "vigilanceSessions":[
        {"id":"v1","startedAt":1790520000000,"completedAt":1790520060000,"score":1e300,"rating":"x","trialCount":1e300,"lapseCount":-1e300,"medianReactionMs":1e300},
        {"id":"v2","startedAt":1790520000000,"completedAt":1790520070000,"score":-1e300,"rating":"x","falseStartCount":9.3e18},
        {"id":"v3","startedAt":-1e300,"completedAt":1790520080000,"score":50,"rating":"Steady"}
      ],
      "prefs":{"halfLife":1e300,"targetSleep":1e300,"cutoffHour":1e300,"dailyLimitMg":1e300},
      "healthSync":{"importedCount":1e300,"lastSyncedAt":1e300},
      "onboarding":{"completed":true,"appWalkthroughStep":1e300,"completedAt":-1e300}
    }}
    """

    @Test func hugeLegacyNumbersImportWithoutTrapping() throws {
        let state = try LegacyState.decode(Self.hugeBlob, now: now)
        // Amounts keep their finite values, as the TypeScript validators did.
        // A time outside JavaScript's Date range marks the record malformed;
        // the edge of that range is kept.
        #expect(state.doses.map(\.id).sorted() == ["ancient", "big", "big2", "edge"])
        #expect(state.sleeps.map(\.id) == ["manual:sleep:2:b"])
        #expect(state.vigilanceSessions.map(\.id).sorted() == ["v1", "v2"])
        #expect(state.healthSync.lastSyncedAt == nil)
        #expect(state.onboarding.completedAt == nil)
        // Scores and counts are pulled back into range.
        #expect(state.vigilanceSessions.map(\.score).sorted() == [0, 100])
        #expect(state.vigilanceSessions.allSatisfy { $0.trialCount >= 0 && $0.lapseCount >= 0 && $0.falseStartCount >= 0 })
        #expect(state.vigilanceSessions.first { $0.id == "v1" }?.rating == .sharp)
        #expect(state.vigilanceSessions.first { $0.id == "v2" }?.rating == .sluggish)
        #expect(state.healthSync.importedCount >= 0)
        #expect(state.onboarding.appWalkthroughStep == 9)
        // It also saves and loads.
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
    }

    @Test func hugeNumbersReachEveryScreenWithoutTrapping() throws {
        let state = try LegacyState.decode(Self.hugeBlob, now: now)
        let inputs = EstimateInputs(prefs: state.prefs, clock: utc)
        _ = Summary.estimateAlertness(at: now, doses: state.doses, sleeps: state.sleeps, inputs: inputs)
        _ = Summary.cutoffAnnotation(now: now, cutoffHour: state.prefs.cutoffHour, doses: state.doses, clock: utc, formatTime: fixtureTime)
        let today = TodayCaffeineSeries.make(doses: state.doses, halfLifeHours: state.prefs.halfLife, now: now, clock: utc)
        _ = Summary.describeCaffeineDay(series: today.series, doses: state.doses, dayStart: utc.startOfDay(now), dayEnd: utc.startOfDay(now) + dayMs, formatTime: fixtureTime)
        _ = CaffeineLog.loggedToday(state.doses, now: now, clock: utc, formatTime: fixtureTime)
        _ = CaffeineLog.todayTotal(state.doses, now: now, clock: utc)
        _ = SummarySignals.caffeineLogged(doses: state.doses, now: now, clock: utc, formatTime: fixtureTime)
        _ = SummarySignals.sleep(sleeps: state.sleeps, targetSleepHours: state.prefs.targetSleep, now: now, clock: utc, text: fixtureText)
        _ = SummarySignals.reactionTest(sessions: state.vigilanceSessions, now: now, clock: utc, text: fixtureText)
        for range in InsightsRange.allCases {
            let insights = Insights.presentation(doses: state.doses, vigilanceSessions: state.vigilanceSessions, range: range, now: now, clock: utc, text: fixtureText)
            #expect(insights.points.allSatisfy { ($0.mg ?? 0) >= 0 })
        }
        for range in SleepRange.allCases {
            _ = SleepModel.presentation(sessions: state.sleeps, targetSleepHours: state.prefs.targetSleep, range: range, now: now, clock: utc, text: fixtureText)
            _ = SleepModel.caffeineImpact(sessions: state.sleeps, doses: state.doses, range: range, now: now, clock: utc)
        }
        _ = SleepModel.caffeineTimingSignal(sleeps: state.sleeps, doses: state.doses, now: now, clock: utc)
        _ = SleepModel.recentNightSignal(sleeps: state.sleeps, targetSleepHours: state.prefs.targetSleep, now: now, clock: utc, text: fixtureText)
        // The -8.64e15 dose is about 100 million days back; filling that span
        // would hang. Only recorded days are listed instead.
        let rows = Export.dailyTotalRows(state.doses, now: now, clock: utc)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.mg != nil })
        _ = Export.dailyTotalsCSV(rows)
        _ = Export.doseEntriesCSV(state.doses, clock: utc)
        _ = Export.vigilanceSessionsCSV(state.vigilanceSessions)
        #expect(OnboardingCopy.formatSleepTarget(state.prefs.targetSleep).value == String(Int.max))
        #expect(formatHoursMinutes(durationMs: 1e300).hasSuffix("m"))
        #expect(formatHoursMinutes(durationMs: -1e300).hasSuffix("m"))
        #expect(formatSleepHours(-1e300).hasSuffix("m"))
        // Ordinary values keep the floor-division results.
        #expect(formatHoursMinutes(durationMs: 7 * hourMs + 5 * minuteMs) == "7h 5m")
        #expect(formatHoursMinutes(durationMs: -90 * minuteMs) == "-2h 30m")
        #expect(formatHoursMinutes(durationMs: 0) == "0h 0m")
        #expect(formatGap(durationMs: -1e300).hasSuffix("m"))
    }

    @Test func dailyRowsFillGapsUpToTheCap() {
        let today = utc.startOfDay(now)
        let recent = [Dose(id: "a", timestamp: today - 10 * dayMs + hourMs, mg: 95)]
        let rows = Export.dailyTotalRows(recent, now: now, clock: utc)
        #expect(rows.count == 11)
        #expect(rows.first?.mg == 95)
        #expect(rows.dropFirst().allSatisfy { $0.mg == nil && $0.entries == 0 })

        // Exactly at the cap the span is still filled, one row per day.
        let atCap = [Dose(id: "b", timestamp: utc.addingDays(-Export.maxFilledDays, to: today), mg: 60)]
        #expect(Export.dailyTotalRows(atCap, now: now, clock: utc).count == Export.maxFilledDays + 1)
    }

    @Test func dailyRowsListOnlyRecordedDaysPastTheCap() {
        let today = utc.startOfDay(now)
        let old = utc.addingDays(-(Export.maxFilledDays + 1), to: today)
        let doses = [
            Dose(id: "ancient-1", timestamp: -8.64e15, mg: 50),
            Dose(id: "ancient-2", timestamp: -8.64e15 + hourMs, mg: 25),
            Dose(id: "old", timestamp: old, mg: 70),
            Dose(id: "today", timestamp: now - hourMs, mg: 95),
            Dose(id: "demo:dose:1", timestamp: now - 2 * hourMs, mg: 60),
        ]
        let rows = Export.dailyTotalRows(doses, now: now, clock: utc)
        // Every recorded day, oldest first, and nothing invented between them.
        #expect(rows.map(\.mg) == [75, 70, 155])
        #expect(rows.map(\.entries) == [2, 1, 2])
        #expect(rows.last?.date == utc.isoDay(now))
        #expect(rows.last?.source == RecordSource.of(ids: ["today", "demo:dose:1"])?.rawValue)
        #expect(!Export.dailyTotalsCSV(rows).contains("no record"))
    }

    /// Noon UTC on a Gregorian date, BC when `bc`.
    static func noon(_ year: Int, _ month: Int, _ day: Int, bc: Bool = false) -> Millis {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(era: bc ? 0 : 1, year: year, month: month, day: day, hour: 12))!
        return date.timeIntervalSince1970 * 1000
    }

    @Test func bcAndAdTwinsGetDistinctDays() {
        let ad = Self.noon(2026, 9, 27)
        let bc = Self.noon(2026, 9, 27, bc: true)
        #expect(bc < -1e14 && bc >= -8.64e15)
        // Foundation's .year is within the era, so both used to read 2026.
        #expect(utc.dayKey(ad) != utc.dayKey(bc))
        #expect(utc.calendarDay(bc).year == -2025)
        #expect(utc.isoDay(ad) == "2026-09-27")
        #expect(utc.isoDay(bc) == "-002025-09-27")
        #expect(utc.isoDay(Self.noon(1, 1, 1, bc: true)) == "0000-01-01")
        #expect(utc.isoDay(Self.noon(1, 1, 1)) == "0001-01-01")
    }

    @Test func isoTimestampsMatchToISOString() {
        #expect(isoTimestamp(0) == "1970-01-01T00:00:00.000Z")
        #expect(isoTimestamp(now) == "2026-09-27T16:41:00.000Z")
        #expect(isoTimestamp(-1500) == "1969-12-31T23:59:58.500Z")
        #expect(isoTimestamp(1_790_527_260_123.9) == "2026-09-27T16:41:00.123Z")
        #expect(isoTimestamp(Self.noon(2026, 9, 27, bc: true)) == "-002025-09-27T12:00:00.000Z")
        #expect(isoTimestamp(Self.noon(1, 1, 1, bc: true)) == "0000-01-01T12:00:00.000Z")
        #expect(isoTimestamp(8.64e15) == "+275760-09-13T00:00:00.000Z")
    }

    @Test func bcTwinsExportAsSeparateDays() {
        let ad = Dose(id: "ad", timestamp: Self.noon(2026, 9, 1), mg: 95)
        let bc = Dose(id: "bc", timestamp: Self.noon(2026, 9, 1, bc: true), mg: 40)
        let rows = Export.dailyTotalRows([ad, bc], now: now, clock: utc)
        #expect(rows.map(\.date) == ["-002025-09-01", "2026-09-01"])
        #expect(rows.map(\.mg) == [40, 95])
        #expect(rows.map(\.entries) == [1, 1])
        let csv = Export.doseEntriesCSV([ad, bc], clock: utc)
        #expect(csv.contains("-002025-09-01T12:00:00.000Z"))
        #expect(csv.contains("2026-09-01T12:00:00.000Z"))
    }

    @Test func bcTwinsStayOutOfRecentWindows() {
        let today = Dose(id: "ad", timestamp: now - hourMs, mg: 95)
        let twin = Dose(id: "bc", timestamp: Self.noon(2026, 9, 27, bc: true), mg: 400)
        for range in InsightsRange.allCases {
            let insights = Insights.presentation(doses: [today, twin], vigilanceSessions: [], range: range, now: now, clock: utc, text: fixtureText)
            #expect(insights.points.compactMap(\.mg).reduce(0, +) == 95)
            #expect(insights.points.map(\.entries).reduce(0, +) == 1)
        }
        let wake = Self.noon(2026, 9, 27, bc: true)
        let sleep = SleepSession(id: "manual:sleep:1:bc", start: wake - 8 * hourMs, end: wake)
        let week = SleepModel.presentation(sessions: [sleep], targetSleepHours: 8, range: .week, now: now, clock: utc, text: fixtureText)
        #expect(week.recordedNights == 0)
        #expect(week.points.allSatisfy { $0.durationMs == nil })
    }

    @Test(arguments: [1e35, 1e100, 1e300, -1e300, 8.64e15 + 1, -8.64e15 - 1, .nan, .infinity, -.infinity])
    func timesWithoutADateFormatBlank(ms: Double) {
        // Past ~1e35 the millisecond remainder cancels to a value Int can't
        // hold; these must come back blank, not trap.
        #expect(!isValidRecordTime(ms))
        #expect(isoTimestamp(ms) == "")
        #expect(utc.isoDay(ms) == "")
        let day = utc.calendarDay(ms)
        #expect(day.year == 0 && day.month == 0 && day.day == 0)
    }

    @Test func theDateRangeEdgesStillFormat() {
        #expect(isoTimestamp(8.64e15) == "+275760-09-13T00:00:00.000Z")
        let earliest = isoTimestamp(-8.64e15)
        #expect(earliest.hasPrefix("-27") && earliest.hasSuffix("T00:00:00.000Z"))
        #expect(!utc.isoDay(-8.64e15).isEmpty)
        #expect(isoTimestamp(1_790_527_260_123.9) == "2026-09-27T16:41:00.123Z")
    }

    /// Records as a hand-edited state.json can hold them: JSONDecoder takes
    /// any finite number, and tests can also build NaN directly.
    static let undateable: [Dose] = [
        Dose(id: "ok", timestamp: now - hourMs, mg: 95),
        Dose(id: "huge", timestamp: 1e300, mg: 60),
        Dose(id: "negative", timestamp: -1e100, mg: 40),
        Dose(id: "nan", timestamp: .nan, mg: 30),
    ]

    @Test func everyCSVExportHandlesUndateableRecords() {
        let entries = Export.doseEntriesCSV(Self.undateable, clock: utc)
        let lines = entries.split(separator: "\n")
        // Finite records keep their row; the date and time cells are blank.
        #expect(lines.count == 4)
        let huge = lines.first { $0.hasPrefix("\"huge\"") }
        #expect(huge?.contains("\"\",\"1e+300\",\"\"") == true)
        #expect(lines.contains { $0.hasPrefix("\"ok\"") && $0.contains("2026-09-27") })

        let rows = Export.dailyTotalRows(Self.undateable, now: now, clock: utc)
        #expect(rows.map(\.mg) == [95])
        _ = Export.dailyTotalsCSV(rows)

        let sessions = [
            VigilanceSession(id: "v", startedAt: 1e300, completedAt: .infinity, durationMs: 60_000, trialCount: 1,
                             validReactionCount: 1, falseStartCount: 0, lapseCount: 0, medianReactionMs: 300,
                             meanReactionMs: 300, fastestReactionMs: 300, reactionStdDevMs: 0, score: 80, rating: .sharp),
        ]
        let vigilance = Export.vigilanceSessionsCSV(sessions)
        #expect(vigilance.split(separator: "\n").last?.hasPrefix("\"v\",\"\",\"\"") == true)
    }

    @Test func loadingDropsRecordsWithoutADate() throws {
        var state = AppState()
        state.doses = Self.undateable.filter { !$0.timestamp.isNaN }
        state.sleeps = [
            SleepSession(id: "manual:sleep:1:a", start: now - 8 * hourMs, end: now - hourMs),
            SleepSession(id: "manual:sleep:2:b", start: -1e300, end: now),
        ]
        state.vigilanceSessions = [
            VigilanceSession(id: "v", startedAt: 1e300, completedAt: 1e300 + 1, durationMs: 1, trialCount: 0,
                             validReactionCount: 0, falseStartCount: 0, lapseCount: 0, medianReactionMs: nil,
                             meanReactionMs: nil, fastestReactionMs: nil, reactionStdDevMs: nil, score: 0, rating: .sluggish),
        ]
        state.onboarding.completedAt = 1e300
        state.healthSync.lastSyncedAt = -1e300
        // It survives a JSON round trip, as a hand-edited file would.
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        let cleaned = decoded.droppingInvalidTimes()
        #expect(cleaned.doses.map(\.id) == ["ok"])
        #expect(cleaned.sleeps.map(\.id) == ["manual:sleep:1:a"])
        #expect(cleaned.vigilanceSessions.isEmpty)
        #expect(cleaned.onboarding.completedAt == nil)
        #expect(cleaned.healthSync.lastSyncedAt == nil)
        #expect(cleaned.droppingInvalidTimes() == cleaned)
        // An ordinary state is left exactly as it was.
        var ordinary = AppState()
        ordinary.loadSampleData(now: now, clock: utc)
        #expect(ordinary.droppingInvalidTimes() == ordinary)
    }

    @Test func emptyKeyIsMalformedNotSkipped() {
        // The reviewer's payload: an empty key, then 1:"A" 1:"B". Skipping the
        // key without its value would read a record A:B that was never written.
        let payload: [UInt8] = [0xFF, 0xFF, 0xFF, 0x07, 0x00, 0x01, 0x41, 0x01, 0x42]
        #expect(throws: MMKVReader.Failure.malformed) { try MMKVReader(data: MMKVMalformedTests.file(payload)) }
        #expect(throws: MMKVReader.Failure.malformed) { try MMKVReader(data: MMKVMalformedTests.file([0xFF, 0xFF, 0xFF, 0x07, 0x00])) }
        // A real pair followed by an empty key fails too, rather than keeping half.
        let tail: [UInt8] = [0xFF, 0xFF, 0xFF, 0x07, 0x01, 0x6B, 0x02, 0x01, 0x41, 0x00, 0x01, 0x42]
        #expect(throws: MMKVReader.Failure.malformed) { try MMKVReader(data: MMKVMalformedTests.file(tail)) }
    }

    @Test func sleepSourceLabelsFollowTheRecordPrefixes() {
        #expect(SleepModel.sourceLabel(id: "demo:sleep:1") == "Sample Data")
        #expect(SleepModel.sourceLabel(id: "demo:other") == "Sample Data")
        #expect(SleepModel.sourceLabel(id: "healthkit:sleep:1:2") == "Health")
        #expect(SleepModel.sourceLabel(id: "manual:sleep:1:a") == "Manual")
        #expect(SleepModel.episodeSourceLabel(ids: ["demo:sleep:1", "manual:sleep:x", "healthkit:sleep:1:2"]) == "Health and Manual and Sample Data")
    }

    @Test func dayBoundsSpanTheLocalDayAcrossDST() {
        // Nov 1 2026 in Los Angeles is 25 hours; Mar 8 2026 is 23.
        let fallBack = localMillis(pacific, 2026, 11, 1, 12)
        let springForward = localMillis(pacific, 2026, 3, 8, 12)
        let fall = pacific.dayBounds(fallBack)
        let spring = pacific.dayBounds(springForward)
        #expect(fall.end - fall.start == 25 * hourMs)
        #expect(spring.end - spring.start == 23 * hourMs)
        #expect(fall.start == pacific.startOfDay(fallBack))
        #expect(utc.dayBounds(now).end - utc.dayBounds(now).start == dayMs)
    }

    @Test func unionDurationCountsOverlapsOnce() {
        let sessions = [
            SleepSession(id: "a", start: 0, end: 10),
            SleepSession(id: "b", start: 5, end: 15),
            SleepSession(id: "c", start: 15, end: 20),
            SleepSession(id: "d", start: 30, end: 31),
        ]
        #expect(SleepModel.unionDuration(sessions) == 21)
        let merged = SleepIntervals.merge(sessions).reduce(0) { $0 + ($1.end - $1.start) }
        #expect(SleepModel.unionDuration(sessions) == merged)
    }
}
