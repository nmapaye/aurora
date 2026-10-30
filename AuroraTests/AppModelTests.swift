import AuroraCore
import Foundation
import Testing
@testable import Aurora

@MainActor
@Suite struct AppModelTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aurora-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private var storeDirectory: URL { root.appendingPathComponent("Support/Aurora", isDirectory: true) }
    private var documents: URL { root.appendingPathComponent("Documents", isDirectory: true) }

    private func makeModel(health: any HealthDataProvider = HealthKitService()) -> AppModel {
        let directory = storeDirectory
        let docs = documents
        return AppModel(
            clock: LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!),
            health: health,
            makeStore: { StateStore(directory: directory) },
            legacy: { LegacyImport(documents: docs) }
        )
    }

    @Test func recordsSurviveRelaunch() throws {
        let first = makeModel()
        first.load()
        #expect(first.phase == .ready)
        let dose = try #require(first.quickAdd(CaffeinePreset.all[1]))
        first.completeOnboarding()

        let second = makeModel()
        second.load()
        #expect(second.state.doses == [dose])
        #expect(second.state.onboarding.completed)
    }

    @Test func storeFolderIsExcludedFromBackup() throws {
        let model = makeModel()
        model.load()
        var directory = storeDirectory
        directory.removeAllCachedResourceValues()
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func quickAddIgnoresADoubleTap() {
        let model = makeModel()
        model.load()
        #expect(model.quickAdd(CaffeinePreset.all[0]) != nil)
        #expect(model.quickAdd(CaffeinePreset.all[0]) == nil)
        #expect(model.state.doses.count == 1)
    }

    @Test func undoRemovesOnlyThatDose() throws {
        let model = makeModel()
        model.load()
        let custom = model.addCustomDose(CustomDoseDraft(mg: "80", source: "Tea", timestamp: AppModel.currentMillis() - 60_000, note: ""))
        let quick = try #require(model.quickAdd(CaffeinePreset.all[0]))
        model.undo(quick)
        #expect(model.state.doses == [custom])
    }

    @Test func sampleEntriesCannotBeCorrected() throws {
        let model = makeModel()
        model.load()
        model.loadSampleData()
        let sample = try #require(model.state.doses.first { RecordID.isSample($0.id) })
        model.correctDose(id: sample.id, with: CustomDoseDraft(mg: "1", source: "", timestamp: sample.timestamp, note: ""))
        model.deleteDose(id: sample.id)
        #expect(model.state.doses.first { $0.id == sample.id } == sample)
    }

    @Test func importsTheReactNativeStore() throws {
        let mmkv = documents.appendingPathComponent("mmkv", isDirectory: true)
        try FileManager.default.createDirectory(at: mmkv, withIntermediateDirectories: true)
        let blob = #"{"state":{"doses":[{"id":"abc","timestamp":1790000000000,"mg":95,"source":"Drip"}],"onboarding":{"completed":true,"appWalkthroughCompleted":true}},"version":6}"#
        try MMKVReader.encode([(key: "aurora/state", value: blob)]).write(to: mmkv.appendingPathComponent("aurora"))

        let model = makeModel()
        model.load()
        #expect(model.state.doses.map(\.id) == ["abc"])
        #expect(model.state.onboarding.completed)
        #expect(FileManager.default.fileExists(atPath: mmkv.path))

        let relaunched = makeModel()
        relaunched.load()
        #expect(relaunched.state.doses.map(\.id) == ["abc"])
    }

    @Test func unreadableLegacyStoreIsKept() throws {
        let mmkv = documents.appendingPathComponent("mmkv", isDirectory: true)
        try FileManager.default.createDirectory(at: mmkv, withIntermediateDirectories: true)
        let file = mmkv.appendingPathComponent("aurora")
        try Data([1, 2]).write(to: file)

        let model = makeModel()
        model.load()
        #expect(model.legacyImportFailed)
        #expect(model.state.doses.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func corruptStateIsPreservedAndRecoveryRequired() throws {
        try StateStore(directory: storeDirectory).prepare()
        try Data("{oops".utf8).write(to: storeDirectory.appendingPathComponent("state.json"))
        let model = makeModel()
        model.load()
        #expect(model.phase == .storageUnavailable)
        #expect(FileManager.default.fileExists(atPath: storeDirectory.appendingPathComponent("state.json").path))
        let files = try FileManager.default.contentsOfDirectory(atPath: storeDirectory.path)
        #expect(files.contains { $0.hasPrefix("state.corrupt.") })
    }

    @Test func deleteAllKeepsSettings() {
        let model = makeModel()
        model.load()
        model.setPrefs { $0.cutoffHour = 12 }
        model.loadSampleData()
        model.deleteAllData()
        #expect(model.state.doses.isEmpty && model.state.sleeps.isEmpty)
        #expect(model.state.prefs.cutoffHour == 12)
    }

    /// The cutoff starts unset; its reminder turns on only once a time is
    /// set, and removing the time turns the reminder off.
    @Test func cutoffReminderNeedsATimeTheyChose() async {
        let directory = storeDirectory
        let backend = RepeatDrinkAppTests.Backend()
        let model = AppModel(
            clock: LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!),
            reminders: ReminderService(backend: backend, defaults: UserDefaults(suiteName: UUID().uuidString)!),
            makeStore: { StateStore(directory: directory) },
            legacy: { nil }
        )
        model.load()
        #expect(model.state.prefs.cutoffHour == nil)
        await model.setReminder(enabled: true)
        #expect(!model.state.prefs.notifyCutoff)
        await model.setCutoffHour(15)
        await model.setReminder(enabled: true)
        #expect(model.state.prefs.notifyCutoff && model.state.prefs.cutoffHour == 15)
        #expect(backend.pending[CutoffReminder.identifier] != nil)
        await model.setCutoffHour(nil)
        #expect(!model.state.prefs.notifyCutoff && model.state.prefs.cutoffHour == nil)
        #expect(backend.pending[CutoffReminder.identifier] == nil)
    }

    @Test func failedSaveRestoresPreviousRecords() throws {
        let model = makeModel(); model.load()
        let first = model.addCustomDose(.init(mg: "80", source: "Tea", timestamp: AppModel.currentMillis() - 60_000, note: ""))
        let file = storeDirectory.appendingPathComponent("state.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        _ = model.addCustomDose(.init(mg: "120", source: "Drip", timestamp: AppModel.currentMillis(), note: ""))
        #expect(model.mutationFailure != nil)
        #expect(model.state.doses == [first])
    }

    @Test func nativeSnapshotRetainsPreviousState() throws {
        let first = makeModel(); first.load()
        let dose = first.addCustomDose(.init(mg: "80", source: "Tea", timestamp: AppModel.currentMillis() - 60_000, note: ""))
        let second = makeModel(); second.load()
        let file = storeDirectory.appendingPathComponent("state.pre-assistant.json")
        let snapshot = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: file))
        #expect(snapshot.doses == [dose])
        second.deleteDose(id: dose.id)
        #expect(try JSONDecoder().decode(AppState.self, from: Data(contentsOf: file)).doses == [dose])
    }

    @Test func invalidDraftCannotBypassUIValidation() {
        let model = makeModel(); model.load()
        _ = model.addCustomDose(.init(mg: "0", source: "Tea", timestamp: AppModel.currentMillis(), note: ""))
        #expect(model.state.doses.isEmpty && model.mutationFailure != nil)
    }

    @Test func versionOneStateMigratesAndKeepsItsSource() throws {
        try StateStore(directory: storeDirectory).prepare()
        let original = Data(#"{"doses":[{"id":"abc","mg":95,"source":"Drip","timestamp":1790000000000}],"schemaVersion":1}"#.utf8)
        try original.write(to: storeDirectory.appendingPathComponent("state.json"))
        let model = makeModel(); model.load()
        #expect(model.phase == .ready && model.state.doses.map(\.id) == ["abc"])
        #expect(model.state.schemaVersion == AppState.schemaVersion)
        #expect(try Data(contentsOf: storeDirectory.appendingPathComponent("state.v1-source.json")) == original)
        #expect(try Data(contentsOf: storeDirectory.appendingPathComponent("state.pre-assistant.json")) == original)
    }

    @Test func stateFromANewerBuildIsLeftUntouched() throws {
        try StateStore(directory: storeDirectory).prepare()
        let future = Data(#"{"schemaVersion":99,"doses":[]}"#.utf8)
        let file = storeDirectory.appendingPathComponent("state.json")
        try future.write(to: file)
        let model = makeModel(); model.load()
        #expect(model.phase == .storageUnavailable)
        #expect(try Data(contentsOf: file) == future)
        #expect(try FileManager.default.contentsOfDirectory(atPath: storeDirectory.path) == ["state.json"])
    }

    @Test func healthCaffeineCannotBeCorrectedDeletedOrUndone() throws {
        var state = AppState()
        let sample = HealthCaffeineSample(
            provenance: HealthSampleProvenance(sampleUUID: "u1", sourceBundleIdentifier: "com.example.tracker"),
            timestamp: AppModel.currentMillis() - 60_000, mg: 80
        )
        state.applyHealthCaffeine(HealthCaffeineChanges(added: [sample], deletedSampleUUIDs: [], anchor: Data()), now: AppModel.currentMillis())
        let imported = try #require(state.doses.first)
        try StateStore(directory: storeDirectory).prepare()
        try StateStore(directory: storeDirectory).save(state)
        let model = makeModel(); model.load()
        model.correctDose(id: imported.id, with: CustomDoseDraft(mg: "1", source: "", timestamp: imported.timestamp, note: ""))
        model.deleteDose(id: imported.id)
        model.undo(imported)
        #expect(model.state.doses == [imported])
    }

    @Test func injectedSleepOnlyProviderImportsSleep() async {
        let end = AppModel.currentMillis() - 60_000
        let provider = SleepOnlyHealth(samples: [HealthSleepSample(start: end - 7 * hourMs, end: end)])
        let model = makeModel(health: provider); model.load()
        await model.connectHealth()
        #expect(model.state.onboarding.permissionStatus == .granted)
        #expect(model.state.sleeps.map(\.id) == [HealthSleepIdentity.id(start: end - 7 * hourMs, end: end)])
        #expect(model.state.healthSync.importedCount == 1)
    }
}

private struct SleepOnlyHealth: HealthDataProvider {
    let samples: [HealthSleepSample]
    var capabilities: HealthCapabilities { [.authorization, .readSleep] }
    var isAvailable: Bool { true }
    func requestAuthorization(read: Set<HealthDataKind>, write: Set<HealthDataKind>) async throws {
        guard read == [.sleepAnalysis], write.isEmpty else { throw HealthProviderError.unsupported("authorization") }
    }
    func sleepSamples(from start: Millis, to end: Millis) async throws -> [HealthSleepSample] { samples }
}
