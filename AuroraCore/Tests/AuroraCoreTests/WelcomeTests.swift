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
        #expect(Welcome.Presentation.holdSeconds <= 1.5)
    }

    // MARK: Setup order, resume and migration

    @Test func setupOrderEndsAtFinish() {
        #expect(SetupStep.allCases.map(\.next) == [.sleepTarget, .health, .calendar, .finish, .finish])
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
