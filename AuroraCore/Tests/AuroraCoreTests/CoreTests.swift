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
