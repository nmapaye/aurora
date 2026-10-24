import Foundation
import Testing
@testable import AuroraCore

struct WelcomeTests {
    static let zones = ["UTC", "America/Los_Angeles"]
    /// Thu, Oct 8, 2026, noon UTC: a plain day with no DST change.
    static let base: Millis = 1_791_460_800_000

    func clock(_ zone: String) -> LocalClock { LocalClock(timeZone: TimeZone(identifier: zone)!) }

    // MARK: Greeting

    @Test(arguments: [(4, Welcome.Daypart.night), (5, .morning), (11, .morning), (12, .afternoon), (17, .afternoon), (18, .evening), (23, .evening), (0, .night)])
    func daypartBoundaries(hour: Int, expected: Welcome.Daypart) {
        #expect(Welcome.Daypart(hour: hour) == expected)
    }

    @Test func greetingUsesCleanedNameOrNone() {
        #expect(Welcome.greeting(daypart: .morning, name: "  Sam  ") == "Good morning, Sam")
        #expect(Welcome.greeting(daypart: .evening, name: "   ") == "Good evening")
        #expect(Welcome.greeting(daypart: .night, name: nil) == "Hello")
        #expect(Welcome.cleanName("Mary   Ann\n") == "Mary Ann")
        #expect(Welcome.cleanName(String(repeating: "a", count: 60))?.count == Welcome.nameLimit)
    }

    // MARK: Evidence

    @Test(arguments: zones) func noRecordsGiveNoEvidenceNeverZero(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 9)
        #expect(Welcome.evidence(state: AppState(), now: now, clock: clock, text: fixtureText) == nil)
        #expect(!Welcome.neutralLine.contains("0"))
    }

    @Test(arguments: zones) func recentSleepWinsWithSourceAndDate(zone: String) throws {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 8)
        let end = now - hourMs - 12 * minuteMs
        var state = AppState()
        state.sleeps = [SleepSession(id: "healthkit:sleep:sample:a", start: now - 8 * hourMs, end: end)]
        state.doses = [Dose(id: "dose:1", timestamp: now - 30 * minuteMs, mg: 95)]
        let evidence = try #require(Welcome.evidence(state: state, now: now, clock: clock, text: fixtureText))
        #expect(evidence.kind == .lastSleep)
        #expect(evidence.text == "6h 48m of recorded sleep")
        #expect(evidence.date == "Ended today, \(fixtureTime(end))")
        #expect(evidence.source == "Health")
        #expect(!evidence.sample)
    }

    /// Health splits a night into stage samples and can add a short one after
    /// waking. The line reports the whole night, not the last fragment.
    @Test(arguments: zones) func sleepLineCoversTheWholeNightNotItsLastFragment(zone: String) throws {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 14, minute: 30)
        let night = clock.setTime(Self.base, hour: 2)
        let wake = clock.setTime(Self.base, hour: 9, minute: 30)
        let fragmentEnd = clock.setTime(Self.base, hour: 9, minute: 39)
        var state = AppState()
        state.sleeps = [
            SleepSession(id: "healthkit:sleep:sample:core", start: night, end: night + 3 * hourMs),
            SleepSession(id: "healthkit:sleep:sample:deep", start: night + 3 * hourMs, end: wake),
            SleepSession(id: "healthkit:sleep:sample:late", start: fragmentEnd - minuteMs, end: fragmentEnd),
        ]
        let evidence = try #require(Welcome.evidence(state: state, now: now, clock: clock, text: fixtureText))
        #expect(evidence.text == "7h 31m of recorded sleep")
        #expect(evidence.date == "Ended today, \(fixtureTime(fragmentEnd))")
        #expect(evidence.source == "Health")
    }

    @Test(arguments: zones) func sleepEndingYesterdayShowsItsDate(zone: String) throws {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 2)
        let end = clock.startOfDay(now) - 30 * minuteMs
        var state = AppState()
        state.sleeps = [SleepSession(id: "manual:sleep:a", start: end - 3 * hourMs, end: end)]
        let evidence = try #require(Welcome.evidence(state: state, now: now, clock: clock, text: fixtureText))
        #expect(evidence.date == "Ended S\(numberText(end)), \(fixtureTime(end))")
        #expect(evidence.source == "Manual")
    }

    @Test(arguments: zones) func napsAndOldOrFutureSleepAreIgnored(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 15)
        var state = AppState()
        state.sleeps = [
            SleepSession(id: "manual:sleep:nap", start: now - 2 * hourMs, end: now - hourMs, type: .nap),
            SleepSession(id: "manual:sleep:old", start: now - 15 * hourMs, end: now - 7 * hourMs),
            SleepSession(id: "manual:sleep:future", start: now + hourMs, end: now + 2 * hourMs),
        ]
        #expect(Welcome.evidence(state: state, now: now, clock: clock, text: fixtureText) == nil)
    }

    @Test(arguments: zones) func caffeineShowsTodaysRecordedTotalAndSources(zone: String) throws {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 19)
        let last = clock.setTime(now, hour: 13, minute: 15)
        var state = AppState()
        state.doses = [
            Dose(id: "healthkit:caffeine:a", timestamp: clock.setTime(now, hour: 8), mg: 95),
            Dose(id: "dose:b", timestamp: last, mg: 60),
            Dose(id: "dose:yesterday", timestamp: clock.addingDays(-1, to: now), mg: 160),
            Dose(id: "dose:later", timestamp: now + hourMs, mg: 70),
        ]
        let evidence = try #require(Welcome.evidence(state: state, now: now, clock: clock, text: fixtureText))
        // Evening still shows the recorded total, never a modeled estimate.
        #expect(evidence.kind == .caffeineToday)
        #expect(evidence.text == "155 mg of caffeine recorded today")
        #expect(evidence.date == "Last today, \(fixtureTime(last))")
        #expect(evidence.source == "Health · Manual")
        #expect(!evidence.sample)
    }

    @Test(arguments: zones) func sampleDataIsLabeledEvenWhenMixed(zone: String) throws {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 10)
        var state = AppState()
        state.doses = [Dose(id: "demo:dose:1", timestamp: now - hourMs, mg: 60), Dose(id: "dose:2", timestamp: now - 2 * hourMs, mg: 30)]
        let caffeine = try #require(Welcome.evidence(state: state, now: now, clock: clock, text: fixtureText))
        #expect(caffeine.sample)
        #expect(caffeine.source == "Manual · Sample Data")
        state.sleeps = [SleepSession(id: "demo:sleep:1", start: now - 9 * hourMs, end: now - 2 * hourMs)]
        let sleep = try #require(Welcome.evidence(state: state, now: now, clock: clock, text: fixtureText))
        #expect(sleep.sample && sleep.source == "Sample Data")
        #expect(sleep.spoken.contains("Source: Sample Data"))
    }

    @Test(arguments: zones) func everyLinePassesCopyRules(zone: String) {
        let clock = clock(zone)
        var state = AppState()
        state.doses = [Dose(id: "dose:a", timestamp: clock.setTime(Self.base, hour: 9), mg: 95)]
        for hour in [3, 9, 14, 20] {
            let now = clock.setTime(Self.base, hour: hour)
            for name in [nil, "Sam"] {
                #expect(CopyRules.violations(in: Welcome.greeting(daypart: .init(hour: hour), name: name)).isEmpty)
            }
            let spoken = Welcome.evidence(state: state, now: now, clock: clock, text: fixtureText)?.spoken ?? Welcome.neutralLine
            #expect(CopyRules.violations(in: spoken).isEmpty)
        }
        var copy = SetupCopy.scenes.flatMap { [$0.title, $0.body] } + [SetupCopy.sampleNote]
        for step in SetupStep.allCases { copy += [SetupCopy.question(step, modelAvailable: true), SetupCopy.question(step, modelAvailable: false)] }
        for line in copy { #expect(CopyRules.violations(in: line).isEmpty, "\(line)") }
    }

    // MARK: Instant skip

    @Test func welcomeShowsOnlyForCompletedSetupWithoutVoiceOver() {
        #expect(Welcome.Presentation.atLaunch(onboardingCompleted: true, voiceOverRunning: false).showing)
        #expect(!Welcome.Presentation.atLaunch(onboardingCompleted: false, voiceOverRunning: false).showing)
        #expect(!Welcome.Presentation.atLaunch(onboardingCompleted: true, voiceOverRunning: true).showing)
    }

    @Test func skipReleasesTouchesAndAccessibilityAtOnce() {
        var welcome = Welcome.Presentation.atLaunch(onboardingCompleted: true, voiceOverRunning: false)
        #expect(welcome.blocksInteraction && welcome.hidesConversationFromAccessibility)
        welcome.skip()
        // Same mutation, no timer: nothing waits for a dissolve.
        #expect(!welcome.showing && !welcome.blocksInteraction && !welcome.hidesConversationFromAccessibility)
        welcome.skip()
        #expect(!welcome.showing)
        // Readable, but still short: a tap always ends it sooner.
        #expect((2.5...3.5).contains(Welcome.Presentation.holdSeconds))
    }

    // MARK: Setup order, resume and migration

    @Test func setupOrderEndsAtFinish() {
        #expect(SetupStep.allCases.map(\.next) == [.sleepTarget, .health, .calendar, .wakeReminders, .finish, .finish])
    }

    @Test func storedStepsResumeIncludingRetiredQuestions() {
        #expect(SetupStep(stored: nil) == .name)
        #expect(SetupStep(stored: -3) == .name)
        #expect(SetupStep(stored: 1) == .sleepTarget)   // retired favorite drinks
        #expect(SetupStep(stored: 3) == .health)        // retired sleep source
        #expect(SetupStep(stored: 5) == .calendar)
        #expect(SetupStep(stored: 99) == .finish)
    }

    @Test func firstRunRouteKeepsCompletedPeopleOut() {
        var onboarding = Onboarding.defaults
        #expect(FirstRun(onboarding) == .story)
        onboarding.setupStep = SetupStep.health.rawValue
        #expect(FirstRun(onboarding) == .setup(.health))
        onboarding.completed = true
        #expect(FirstRun(onboarding) == .done)
        onboarding.setupStep = nil
        #expect(FirstRun(onboarding) == .done)
    }

    @Test func olderFilesWithoutNewFieldsDecodeAndStayComplete() throws {
        let prefs = try JSONDecoder().decode(Prefs.self, from: Data(#"{"halfLife":5,"targetSleep":8,"dailyLimitMg":400,"cutoffHour":16,"notifyCutoff":false}"#.utf8))
        #expect(prefs.displayName == nil && prefs.favoriteDrinkIDs == nil)
        let file = #"{"schemaVersion":2,"prefs":{"halfLife":5,"targetSleep":7.5,"dailyLimitMg":400,"cutoffHour":16,"notifyCutoff":false},"onboarding":{"completed":true,"source":"manual","permissionStatus":"unsupported","appWalkthroughCompleted":true,"appWalkthroughStep":9}}"#
        let state = try JSONDecoder().decode(AppState.self, from: Data(file.utf8))
        #expect(state.onboarding.completed && state.onboarding.setupStep == nil)
        #expect(state.prefs.targetSleep == 7.5)
        #expect(FirstRun(state.onboarding) == .done)
    }

    // MARK: Sleep target without a default

    private func oldFile(target: Double, outcomes: String?) -> Data {
        let setup = outcomes.map { #","setupStep":7,"setupOutcomes":\#($0)"# } ?? ""
        return Data(#"{"schemaVersion":2,"prefs":{"halfLife":5,"targetSleep":\#(target),"dailyLimitMg":400,"cutoffHour":16,"notifyCutoff":false},"onboarding":{"completed":true,"source":"manual","permissionStatus":"unsupported","appWalkthroughCompleted":true,"appWalkthroughStep":9\#(setup)}}"#.utf8)
    }

    @Test func freshStateHasNoSleepTargetAndDoesNotWriteOne() throws {
        #expect(AppState().prefs.targetSleep == nil)
        let encoded = String(decoding: try JSONEncoder().encode(AppState()), as: UTF8.self)
        // Only the downgrade placeholder is written; no chosen target.
        #expect(!encoded.contains("chosenTargetSleep"))
        #expect(encoded.contains(#""targetSleep":8"#))
        #expect(encoded.contains(#""sleepTargetFormat":1"#))
        #expect(OnboardingCopy.sleepTargetRange == 5...11)
        #expect(CopyRules.violations(in: OnboardingCopy.stepCopy(step: 0, source: .manual).body + OnboardingCopy.noSleepTargetNote).isEmpty)
    }

    @Test func eightHoursKeptByNotNowGoesBackToUnset() throws {
        let state = try JSONDecoder().decode(AppState.self, from: oldFile(target: 8, outcomes: #"{"0":"answered","2":"skipped"}"#))
        #expect(state.prefs.targetSleep == nil)
        #expect(state.sleepTargetFormat == SleepTargetMigration.currentFormat)
        // Saved and reopened, it stays unset.
        let reopened = try JSONDecoder().decode(AppState.self, from: StateMigration.encode(state))
        #expect(reopened == state)
        #expect(SetupTranscript.reply(.sleepTarget, .skipped, state: state, healthAvailable: true, calendarsChosen: false)
            == .retained("No sleep target set. You can choose one in Settings."))
    }

    @Test func chosenTargetsAreKeptByTheMigration() throws {
        // Answered at setup, a different value kept by Not now, and a file
        // from before setup outcomes existed: all the person's own.
        for (target, outcomes) in [(8.0, #"{"2":"answered"}"#), (7.5, #"{"2":"skipped"}"#), (8.0, nil as String?)] {
            let state = try JSONDecoder().decode(AppState.self, from: oldFile(target: target, outcomes: outcomes))
            #expect(state.prefs.targetSleep == target)
        }
        // A standalone older Prefs value keeps its number.
        let prefs = try JSONDecoder().decode(Prefs.self, from: Data(#"{"halfLife":5,"targetSleep":8,"dailyLimitMg":400,"cutoffHour":16,"notifyCutoff":false}"#.utf8))
        #expect(prefs.targetSleep == 8)
    }

    @Test func eightHoursChosenLaterInSettingsIsNeverCleared() throws {
        var state = try JSONDecoder().decode(AppState.self, from: oldFile(target: 8, outcomes: #"{"2":"skipped"}"#))
        #expect(state.prefs.targetSleep == nil)
        state.prefs.targetSleep = 8
        let reopened = try JSONDecoder().decode(AppState.self, from: StateMigration.encode(state))
        #expect(reopened.prefs.targetSleep == 8)
    }

    @Test func unsetFieldsAreNotWrittenAndSetOnesRoundTrip() throws {
        let encoded = String(decoding: try JSONEncoder().encode(AppState()), as: UTF8.self)
        for key in ["displayName", "favoriteDrinkIDs", "setupStep"] { #expect(!encoded.contains(key)) }
        var state = AppState()
        state.prefs.displayName = "Sam"
        state.prefs.favoriteDrinkIDs = ["matcha"]
        state.onboarding.setupStep = SetupStep.calendar.rawValue
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
        #expect(decoded.schemaVersion == AppState.schemaVersion)
    }

    // MARK: Truthful transcript

    private func transcript(_ state: AppState, calendars: Bool = false) -> [SetupTranscript.Entry] {
        SetupTranscript.entries(state: state, healthAvailable: true, calendarsChosen: calendars, modelAvailable: true)
    }

    private func setupState(at step: SetupStep) -> AppState {
        var state = AppState()
        state.onboarding.setupStep = step.rawValue
        return state
    }

    @Test func skipToEndShowsNoAnswersForQuestionsNeverAsked() {
        var state = setupState(at: .name)
        state.skipSetupToEnd()
        let entries = transcript(state)
        #expect(entries.map(\.step) == [.finish])
        #expect(entries.allSatisfy { $0.reply == nil })
        #expect(state.prefs.targetSleep == nil)
        #expect(state.onboarding.setupOutcomes == nil)
        #expect(state.onboarding.source == .manual)
    }

    @Test func skipToEndFromMidSetupKeepsOnlyRealOutcomes() {
        var state = setupState(at: .name)
        state.prefs.displayName = "Sam"
        state.recordSetup(.name, .answered)
        state.skipSetupToEnd()
        let entries = transcript(state)
        #expect(entries.map(\.step) == [.name, .finish])
        #expect(entries[0].reply == .person("Sam"))
    }

    @Test func eachStepSkipsOnItsOwnAndKeepsSettings() {
        var state = setupState(at: .name)
        state.prefs.targetSleep = 7
        state.recordSetup(.name, .skipped)
        #expect(SetupStep(stored: state.onboarding.setupStep) == .sleepTarget)
        state.recordSetup(.sleepTarget, .skipped)
        state.recordSetup(.health, .skipped)
        state.recordSetup(.calendar, .skipped)
        state.recordSetup(.wakeReminders, .skipped)
        #expect(SetupStep(stored: state.onboarding.setupStep) == .finish)
        #expect(state.prefs.targetSleep == 7 && state.prefs.displayName == nil && state.prefs.wakeReminders == nil)
        let replies = transcript(state).map(\.reply)
        #expect(replies == [.person("Not now"), .retained("Sleep target stays at 7 hours. You can change it in Settings."), .person("Not now"), .person("Not now"), .person("Not now"), nil])
    }

    @Test func explicitAnswersAreShownAsTheirs() {
        var state = setupState(at: .name)
        state.prefs.displayName = "Sam"
        state.recordSetup(.name, .answered)
        state.prefs.targetSleep = 7.5
        state.recordSetup(.sleepTarget, .answered)
        state.healthChoices.readCaffeine = true
        state.recordSetup(.health, .answered)
        state.recordSetup(.calendar, .answered)
        let replies = transcript(state, calendars: true).map(\.reply)
        #expect(replies == [.person("Sam"), .person("7.5 hours"), .person("Requested: Read caffeine"), .person("Calendars chosen"), nil])
    }

    @Test func outcomesResumeAfterRelaunchAndOldProgressKeepsItsName() throws {
        var state = setupState(at: .name)
        state.prefs.displayName = "Sam"
        state.recordSetup(.name, .answered)
        state.recordSetup(.sleepTarget, .skipped)
        let relaunched = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        #expect(transcript(relaunched) == transcript(state))
        #expect(FirstRun(relaunched.onboarding) == .setup(.health))

        // Progress saved before outcomes were kept: the entered name is
        // known, the sleep target was never confirmed, so it isn't shown.
        let file = #"{"prefs":{"halfLife":5,"targetSleep":8,"dailyLimitMg":400,"cutoffHour":16,"notifyCutoff":false,"displayName":"Sam"},"onboarding":{"completed":false,"source":"healthkit","permissionStatus":"idle","appWalkthroughCompleted":false,"appWalkthroughStep":0,"setupStep":4}}"#
        let older = try JSONDecoder().decode(AppState.self, from: Data(file.utf8))
        #expect(older.onboarding.setupOutcomes == nil)
        #expect(transcript(older).map(\.step) == [.name, .health])
        #expect(transcript(older).first?.reply == .person("Sam"))
    }

    @Test func unknownOutcomeValuesDecodeAndAreIgnored() throws {
        let file = #"{"onboarding":{"completed":false,"source":"healthkit","permissionStatus":"idle","appWalkthroughCompleted":false,"appWalkthroughStep":0,"setupStep":5,"setupOutcomes":{"2":"later","9":"answered"}}}"#
        let state = try JSONDecoder().decode(AppState.self, from: Data(file.utf8))
        #expect(transcript(state).map(\.step) == [.calendar])
    }

    @Test func completedOldUsersStayOutAndOutcomesAreNotWrittenUnset() throws {
        let file = #"{"onboarding":{"completed":true,"source":"manual","permissionStatus":"unsupported","appWalkthroughCompleted":true,"appWalkthroughStep":9}}"#
        let state = try JSONDecoder().decode(AppState.self, from: Data(file.utf8))
        #expect(FirstRun(state.onboarding) == .done)
        #expect(!String(decoding: try JSONEncoder().encode(state), as: UTF8.self).contains("setupOutcomes"))
    }

    @Test func settlingSleepSourceKeepsADeclinedStatusAndReadSleep() {
        var declined = AppState()
        declined.onboarding.source = .manual
        declined.onboarding.permissionStatus = .denied
        declined.settleSetupSleepSource()
        #expect(declined.onboarding.permissionStatus == .denied)
        var reading = AppState()
        reading.healthChoices.readSleep = true
        reading.settleSetupSleepSource()
        #expect(reading.onboarding.source == .healthkit)
    }

    @Test func favoritesComeFirstWithoutDuplicates() {
        #expect(CaffeinePreset.ordered(favorites: ["matcha", "espresso", "matcha", "unknown"]).map(\.id) == ["matcha", "espresso", "drip", "energy"])
        #expect(CaffeinePreset.ordered(favorites: nil).map(\.id) == CaffeinePreset.all.map(\.id))
    }

    // MARK: Health and model availability copy

    @Test func healthCopyNeverClaimsAccess() {
        let off = HealthChoices.off
        #expect(SetupCopy.healthAnswer(off, healthAvailable: true) == "Not now")
        #expect(SetupCopy.healthAnswer(HealthChoices(readSleep: true, writeCaffeine: true), healthAvailable: true) == "Requested: Read sleep, Add my caffeine to Health")
        #expect(SetupCopy.healthAnswer(HealthChoices(readSleep: true), healthAvailable: false) == "Not available on this device")
        let denied = SetupCopy.healthNote(off, healthAvailable: true, permission: .denied, demoMode: false)
        #expect(denied.contains("didn’t finish"))
        let empty = SetupCopy.healthNote(HealthChoices(readCaffeine: true), healthAvailable: true, permission: .idle, demoMode: false)
        #expect(empty.contains("finding nothing can mean no records or no read access"))
        #expect(SetupCopy.healthNote(off, healthAvailable: false, permission: .idle, demoMode: false).contains("isn’t available"))
        #expect(SetupCopy.healthNote(off, healthAvailable: true, permission: .idle, demoMode: true).contains("Sample Data"))
        for line in [denied, empty, SetupCopy.healthNote(off, healthAvailable: true, permission: .idle, demoMode: false)] {
            #expect(!line.lowercased().contains("granted") && !line.lowercased().contains("connected"))
        }
    }

    @Test func finishCopyFollowsModelAvailability() {
        #expect(SetupCopy.question(.finish, modelAvailable: true).contains("Ask me"))
        let unavailable = SetupCopy.question(.finish, modelAvailable: false)
        #expect(unavailable.contains("isn’t available") && unavailable.contains("quick actions"))
        #expect(!unavailable.contains("Ask me"))
    }
}
