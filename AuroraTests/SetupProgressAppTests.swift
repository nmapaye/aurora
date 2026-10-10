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

    @Test func answersResumeAfterRelaunchAndCompletedSetupStaysDone() {
        let health = ScriptedHealth()
        let first = makeModel(health: health)
        #expect(FirstRun(first.state.onboarding) == .story)
        first.setSetupStep(.name)
        first.setDisplayName("  Sam  ")
        first.setSetupStep(.health)

        let relaunched = makeModel(health: health)
        #expect(relaunched.state.prefs.displayName == "Sam")
        #expect(FirstRun(relaunched.state.onboarding) == .setup(.health))
        relaunched.setDisplayName("   ")
        #expect(relaunched.state.prefs.displayName == nil)
        relaunched.completeOnboarding()

        let again = makeModel(health: health)
        #expect(FirstRun(again.state.onboarding) == .done)
        #expect(health.authorizations.isEmpty, "Setup answers alone never ask Health")
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
