import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// First-run setup through AppModel: answers persist and resume, completed
/// people stay out of setup, and Health choices made during setup use the
/// same separate requests as Settings.
@MainActor
@Suite struct SetupProgressAppTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aurora-setup-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func makeModel(health: any HealthDataProvider) -> AppModel {
        let directory = root.appendingPathComponent("Support/Aurora", isDirectory: true)
        let docs = root.appendingPathComponent("Documents", isDirectory: true)
        let model = AppModel(
            clock: LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!),
            health: health,
            makeStore: { StateStore(directory: directory) },
            legacy: { LegacyImport(documents: docs) }
        )
        model.load()
        return model
    }

    private var stateFile: URL { root.appendingPathComponent("Support/Aurora/state.json") }

    /// Every later save fails: the state file's path becomes a directory.
    private func breakSaving() throws {
        try FileManager.default.removeItem(at: stateFile)
        try FileManager.default.createDirectory(at: stateFile, withIntermediateDirectories: false)
    }

    private func restoreSaving() throws {
        try FileManager.default.removeItem(at: stateFile)
    }

    private func transcript(_ model: AppModel) -> [SetupTranscript.Entry] {
        SetupTranscript.entries(state: model.state, healthAvailable: true, calendarsChosen: false, modelAvailable: true)
    }

    @Test func answersResumeAfterRelaunchAndCompletedSetupStaysDone() {
        let health = ScriptedHealth()
        let first = makeModel(health: health)
        #expect(FirstRun(first.state.onboarding) == .story)
        #expect(first.setSetupStep(.name))
        #expect(first.recordSetup(.name, .answered) { $0.prefs.displayName = Welcome.cleanName("  Sam  ") })
        #expect(first.recordSetup(.sleepTarget, .skipped))

        let relaunched = makeModel(health: health)
        #expect(relaunched.state.prefs.displayName == "Sam")
        #expect(relaunched.state.prefs.targetSleep == Prefs.defaultTargetSleep)
        #expect(FirstRun(relaunched.state.onboarding) == .setup(.health))
        #expect(transcript(relaunched).map(\.reply) == [.person("Sam"), .retained("Sleep target stays at 8 hours. You can change it in Settings."), nil])
        #expect(relaunched.finishSetup(withSampleData: false))

        let again = makeModel(health: health)
        #expect(FirstRun(again.state.onboarding) == .done)
        #expect(health.authorizations.isEmpty, "Setup answers alone never ask Health")
    }

    @Test func skipToEndInventsNoAnswers() {
        let model = makeModel(health: ScriptedHealth())
        #expect(model.setSetupStep(.name))
        #expect(model.skipSetupToEnd())
        #expect(transcript(model).map(\.step) == [.finish])
        #expect(model.state.prefs.targetSleep == Prefs.defaultTargetSleep && model.state.prefs.displayName == nil)
        #expect(model.state.onboarding.setupOutcomes == nil)
        #expect(model.state.onboarding.source == .manual)
    }

    @Test func failedNameSaveKeepsTheQuestionAndNothingAdvances() throws {
        let model = makeModel(health: ScriptedHealth())
        #expect(model.setSetupStep(.name))
        try breakSaving()
        #expect(!model.recordSetup(.name, .answered) { $0.prefs.displayName = "Sam" })
        #expect(model.mutationFailure != nil)
        #expect(model.state.prefs.displayName == nil)
        #expect(SetupStep(stored: model.state.onboarding.setupStep) == .name)
        #expect(model.state.onboarding.setupOutcomes == nil)

        // Retrying after storage recovers saves the name and the step together.
        try restoreSaving()
        #expect(model.recordSetup(.name, .answered) { $0.prefs.displayName = "Sam" })
        #expect(model.mutationFailure == nil)
        let relaunched = makeModel(health: ScriptedHealth())
        #expect(relaunched.state.prefs.displayName == "Sam")
        #expect(FirstRun(relaunched.state.onboarding) == .setup(.sleepTarget))
    }

    @Test func failedSkipsDoNotAdvanceOrRecordOutcomes() throws {
        let model = makeModel(health: ScriptedHealth())
        #expect(model.setSetupStep(.sleepTarget))
        try breakSaving()
        #expect(!model.recordSetup(.sleepTarget, .skipped))
        #expect(!model.skipSetupToEnd())
        #expect(!model.setSetupStep(.health))
        #expect(model.mutationFailure != nil)
        #expect(SetupStep(stored: model.state.onboarding.setupStep) == .sleepTarget)
        #expect(model.state.onboarding.setupOutcomes == nil)
        #expect(model.state.onboarding.source == .healthkit)
    }

    @Test func failedFinishLeavesSetupOpenWithoutSampleData() throws {
        let model = makeModel(health: ScriptedHealth())
        #expect(model.setSetupStep(.finish))
        try breakSaving()
        #expect(!model.finishSetup(withSampleData: true))
        #expect(!model.completeOnboarding())
        #expect(model.mutationFailure != nil)
        #expect(!model.state.onboarding.completed)
        #expect(!model.state.demoMode && model.state.doses.isEmpty)
        #expect(FirstRun(model.state.onboarding) == .setup(.finish))

        try restoreSaving()
        #expect(model.finishSetup(withSampleData: true))
        #expect(model.state.onboarding.completed && model.state.demoMode)
        #expect(model.state.doses.allSatisfy { RecordID.isSample($0.id) && $0.timestamp <= model.now })
    }

    @Test func noRecordsAndSampleDataGiveHonestWelcomeEvidence() {
        let model = makeModel(health: ScriptedHealth())
        model.completeOnboarding()
        #expect(Welcome.evidence(state: model.state, now: model.now, clock: model.clock, text: model.text) == nil)
        model.loadSampleData()
        if let evidence = Welcome.evidence(state: model.state, now: model.now, clock: model.clock, text: model.text) {
            #expect(evidence.sample && evidence.source.contains("Sample Data"))
        }
    }

    @Test func healthChoicesDuringSetupRequestOnlyTheirOwnPermission() async {
        let health = ScriptedHealth()
        let model = makeModel(health: health)
        model.setSetupStep(.health)
        #expect(await model.setHealthChoice(.readCaffeine, enabled: true) == .requested)
        #expect(health.authorizations.last?.read == [.caffeine] && health.authorizations.last?.write.isEmpty == true)
        #expect(await model.setHealthChoice(.writeCaffeine, enabled: true) == .requested)
        #expect(health.authorizations.last?.write == [.caffeine] && health.authorizations.last?.read.isEmpty == true)
        #expect(!model.state.healthChoices.readSleep)
        #expect(SetupCopy.healthAnswer(model.state.healthChoices, healthAvailable: true) == "Requested: Read caffeine, Add my caffeine to Health")
        #expect(!model.state.onboarding.completed)
    }

    @Test func declinedSleepRequestIsReportedWithoutClaimingAccess() async {
        let model = makeModel(health: DecliningHealth())
        model.setSetupStep(.health)
        _ = await model.setHealthChoice(.readSleep, enabled: true)
        #expect(!model.state.healthChoices.readSleep)
        #expect(model.state.onboarding.source == .manual)
        #expect(model.state.onboarding.permissionStatus == .denied)
        #expect(model.recordSetup(.health, .skipped) { $0.settleSetupSleepSource() })
        #expect(model.state.onboarding.permissionStatus == .denied)
        let note = SetupCopy.healthNote(model.state.healthChoices, healthAvailable: true, permission: model.state.onboarding.permissionStatus, demoMode: false)
        #expect(note.contains("didn’t finish"))
    }
}

private struct DecliningHealth: HealthDataProvider {
    var capabilities: HealthCapabilities { [.authorization, .readSleep] }
    var isAvailable: Bool { true }
    func requestAuthorization(read: Set<HealthDataKind>, write: Set<HealthDataKind>) async throws {
        throw HealthProviderError.unsupported("authorization")
    }
    func sleepSamples(from start: Millis, to end: Millis) async throws -> [HealthSleepSample] { [] }
}
