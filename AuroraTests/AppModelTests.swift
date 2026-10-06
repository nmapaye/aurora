import AuroraCore
import Foundation
import HealthKit
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

    private var stateFile: URL { storeDirectory.appendingPathComponent("state.json") }
    private var mmkv: URL { documents.appendingPathComponent("mmkv", isDirectory: true) }
    private var legacyFile: URL { mmkv.appendingPathComponent("aurora") }

    private func makeModel(uiTestReset: Bool = false, afterTemporaryWrite: @escaping (URL) throws -> Void = { _ in }) -> AppModel {
        let directory = storeDirectory
        let docs = documents
        return AppModel(
            clock: LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!),
            makeStore: { StateStore(directory: directory, afterTemporaryWrite: afterTemporaryWrite) },
            legacy: { LegacyImport(documents: docs) },
            uiTestReset: uiTestReset
        )
    }

    private static let legacyBlob = #"{"state":{"doses":[{"id":"abc","timestamp":1790000000000,"mg":95,"source":"Drip"}],"onboarding":{"completed":true,"appWalkthroughCompleted":true}},"version":6}"#

    /// The React Native store, with the corrupt-copy key its storage adapter kept.
    private func writeLegacyStore(_ blob: String = legacyBlob) throws {
        try FileManager.default.createDirectory(at: mmkv, withIntermediateDirectories: true)
        try MMKVReader.encode([
            (key: "aurora/state.corrupt.1790000000000", value: "{bad"),
            (key: "aurora/state", value: blob),
        ]).write(to: legacyFile)
        try Data(repeating: 0, count: 8).write(to: mmkv.appendingPathComponent("aurora.crc"))
    }

    private func savedState() throws -> AppState {
        try JSONDecoder().decode(AppState.self, from: Data(contentsOf: stateFile))
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

    @Test func importsTheReactNativeStoreAndKeepsIt() throws {
        try writeLegacyStore()
        let original = try Data(contentsOf: legacyFile)

        let model = makeModel()
        model.load()
        #expect(model.phase == .ready)
        #expect(model.state.doses.map(\.id) == ["abc"])
        #expect(model.state.onboarding.completed)
        // Saved and read back before anything else, and the old store is untouched.
        #expect(try savedState() == model.state)
        #expect(try Data(contentsOf: legacyFile) == original)
        #expect(FileManager.default.fileExists(atPath: mmkv.appendingPathComponent("aurora.crc").path))

        let relaunched = makeModel()
        relaunched.load()
        #expect(relaunched.state.doses.map(\.id) == ["abc"])
    }

    @Test func migratedStateWinsOverTheOldStore() throws {
        try writeLegacyStore()
        let model = makeModel()
        model.load()
        model.deleteDose(id: "abc")
        // The old store still holds "abc"; state.json existing ends the migration.
        let relaunched = makeModel()
        relaunched.load()
        #expect(relaunched.state.doses.isEmpty)
    }

    @Test func unreadableLegacyStoreBlocksWritesAndIsRetried() throws {
        try FileManager.default.createDirectory(at: mmkv, withIntermediateDirectories: true)
        try Data([1, 2]).write(to: legacyFile)

        let model = makeModel()
        model.load()
        #expect(model.phase == .recovery(.legacyUnreadable))
        #expect(model.quickAdd(CaffeinePreset.all[0]) == nil)
        model.setPrefs { $0.cutoffHour = 9 }
        #expect(!FileManager.default.fileExists(atPath: stateFile.path))
        #expect(try Data(contentsOf: legacyFile) == Data([1, 2]))

        // The next launch tries again, and succeeds once the file reads.
        try writeLegacyStore()
        let relaunched = makeModel()
        relaunched.load()
        #expect(relaunched.phase == .ready)
        #expect(relaunched.state.doses.map(\.id) == ["abc"])
    }

    @Test func startingFreshAfterAFailedImportKeepsTheOldStore() throws {
        try FileManager.default.createDirectory(at: mmkv, withIntermediateDirectories: true)
        try Data([1, 2]).write(to: legacyFile)
        let model = makeModel()
        model.load()
        model.startFresh()
        #expect(model.phase == .ready)
        #expect(try savedState() == AppState())
        #expect(try Data(contentsOf: legacyFile) == Data([1, 2]))
    }

    /// An MMKV file built byte by byte: the header, MMKV's placeholder, then
    /// each key with its raw value bytes.
    private func writeRawLegacyStore(_ pairs: [(String, [UInt8])]) throws {
        try FileManager.default.createDirectory(at: mmkv, withIntermediateDirectories: true)
        var payload: [UInt8] = [0xFF, 0xFF, 0xFF, 0x07]
        for (key, value) in pairs {
            payload += [UInt8(key.utf8.count)] + Array(key.utf8) + [UInt8(value.count)] + value
        }
        let size = UInt32(payload.count)
        try Data([UInt8(size & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 24 & 0xFF)] + payload)
            .write(to: legacyFile)
    }

    @Test func legacyStateThatIsNotUTF8IsUnreadableNotEmpty() throws {
        try writeRawLegacyStore([("aurora/state", [0x02, 0xFF, 0xFE])])
        let original = try Data(contentsOf: legacyFile)
        let model = makeModel()
        model.load()
        #expect(model.phase == .recovery(.legacyUnreadable))
        #expect(!FileManager.default.fileExists(atPath: stateFile.path))
        #expect(try Data(contentsOf: legacyFile) == original)
    }

    @Test func legacyStoreWithOnlyKeptCopiesIsUnreadable() throws {
        try FileManager.default.createDirectory(at: mmkv, withIntermediateDirectories: true)
        try MMKVReader.encode([(key: "aurora/state.corrupt.1790000000000", value: "{bad")]).write(to: legacyFile)
        let model = makeModel()
        model.load()
        #expect(model.phase == .recovery(.legacyUnreadable))
        #expect(!FileManager.default.fileExists(atPath: stateFile.path))

        // Relaunching tries again rather than treating the store as empty.
        let relaunched = makeModel()
        relaunched.load()
        #expect(relaunched.phase == .recovery(.legacyUnreadable))
    }

    @Test func emptyLegacyStoreIsNotAFailure() throws {
        try FileManager.default.createDirectory(at: mmkv, withIntermediateDirectories: true)
        try MMKVReader.encode([(key: "other", value: "x")]).write(to: legacyFile)
        let model = makeModel()
        model.load()
        #expect(model.phase == .ready)
        #expect(model.state == AppState())
    }

    @Test func corruptStateIsKeptAndBlocksWrites() throws {
        try StateStore(directory: storeDirectory).prepare()
        try Data("{oops".utf8).write(to: stateFile)
        let model = makeModel()
        model.load()
        #expect(model.phase == .recovery(.corrupt(backupKept: true)))
        let store = StateStore(directory: storeDirectory)
        let backups = store.corruptBackups()
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: backups[0]) == Data("{oops".utf8))

        // Nothing writes over the damaged file until the person chooses.
        #expect(model.quickAdd(CaffeinePreset.all[0]) == nil)
        model.loadSampleData()
        #expect(try Data(contentsOf: stateFile) == Data("{oops".utf8))

        // Retrying keeps one copy, then starting fresh replaces state.json only.
        model.retryStorage()
        #expect(store.corruptBackups().count == 1)
        model.startFresh()
        #expect(model.phase == .ready)
        #expect(try savedState() == AppState())
        #expect(!store.corruptBackups().isEmpty)
    }

    @Test func unreadableStateOffersOnlyRetry() throws {
        // A directory where the file should be: it exists but can't be read.
        try FileManager.default.createDirectory(at: stateFile, withIntermediateDirectories: true)
        let model = makeModel()
        model.load()
        #expect(model.phase == .recovery(.unreadable))
        #expect(!AppModel.Recovery.unreadable.allowsStartFresh)
        model.startFresh()
        #expect(model.phase == .recovery(.unreadable))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: stateFile.path, isDirectory: &isDirectory) && isDirectory.boolValue)

        try FileManager.default.removeItem(at: stateFile)
        model.retryStorage()
        #expect(model.phase == .ready)
    }

    @Test func failedSavesAreSurfacedAndRetried() throws {
        let model = makeModel()
        model.load()
        model.completeOnboarding()
        #expect(!model.saveFailed)
        // A read-only folder makes the atomic write fail.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: storeDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: storeDirectory.path) }
        let dose = try #require(model.quickAdd(CaffeinePreset.all[0]))
        #expect(model.saveFailed)
        #expect(try savedState().doses.isEmpty)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: storeDirectory.path)
        model.retrySave()
        #expect(!model.saveFailed)
        #expect(try savedState().doses == [dose])
    }

    @Test func aMismatchedWriteLeavesThePreviousStateInPlace() throws {
        let first = makeModel()
        first.load()
        first.completeOnboarding()
        let good = try Data(contentsOf: stateFile)

        // The temporary file decodes, but to a different state.
        let other = try JSONEncoder().encode(AppState())
        let model = makeModel(afterTemporaryWrite: { try other.write(to: $0) })
        model.load()
        _ = model.quickAdd(CaffeinePreset.all[0])
        #expect(model.saveFailed)
        #expect(try Data(contentsOf: stateFile) == good)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: storeDirectory.path).filter { $0.contains("saving") }
        #expect(leftovers.isEmpty)
    }

    @Test func loadingLeavesAnUnfinishedSaveInPlace() throws {
        let first = makeModel()
        first.load()
        first.completeOnboarding()
        let orphan = storeDirectory.appendingPathComponent("state.json.saving-XYZ")
        try Data("partial".utf8).write(to: orphan)

        let relaunched = makeModel()
        relaunched.load()
        #expect(relaunched.phase == .ready)
        #expect(try Data(contentsOf: orphan) == Data("partial".utf8))
        _ = relaunched.quickAdd(CaffeinePreset.all[0])
        #expect(!relaunched.saveFailed)
        #expect(FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test func aFailedSwapLeavesThePreviousState() throws {
        let first = makeModel()
        first.load()
        first.completeOnboarding()
        let good = try Data(contentsOf: stateFile)
        // The temporary file is written and checked, then the folder turns
        // read-only, so the rename that swaps it in fails.
        let directory = storeDirectory
        let model = makeModel(afterTemporaryWrite: { _ in
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        })
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: storeDirectory.path) }
        model.load()
        _ = model.quickAdd(CaffeinePreset.all[0])
        #expect(model.saveFailed)
        #expect(try Data(contentsOf: stateFile) == good)
    }

    @Test func aFailedImportSaveLeavesNoStateAndIsRetried() throws {
        try writeLegacyStore()
        let other = try JSONEncoder().encode(AppState())
        let model = makeModel(afterTemporaryWrite: { try other.write(to: $0) })
        model.load()
        #expect(model.phase == .recovery(.importNotSaved))
        #expect(!FileManager.default.fileExists(atPath: stateFile.path))

        let relaunched = makeModel()
        relaunched.load()
        #expect(relaunched.phase == .ready)
        #expect(relaunched.state.doses.map(\.id) == ["abc"])
    }

    @Test func startFreshFailureIsShownInRecovery() throws {
        try StateStore(directory: storeDirectory).prepare()
        try Data("{oops".utf8).write(to: stateFile)
        let model = makeModel(afterTemporaryWrite: { _ in throw CocoaError(.fileWriteNoPermission) })
        model.load()
        #expect(model.phase == .recovery(.corrupt(backupKept: true)))
        model.startFresh()
        #expect(model.startFreshFailed)
        #expect(model.phase == .recovery(.corrupt(backupKept: true)))
        #expect(try Data(contentsOf: stateFile) == Data("{oops".utf8))
        model.retryStorage()
        #expect(!model.startFreshFailed)
    }

    @Test func uiTestResetRunsBeforeMigrationAndLeavesTheOldStore() throws {
        try writeLegacyStore()
        let original = try Data(contentsOf: legacyFile)
        let first = makeModel()
        first.load()
        #expect(first.state.doses.count == 1)

        let reset = makeModel(uiTestReset: true)
        reset.load()
        #expect(reset.phase == .ready)
        #expect(reset.state == AppState())
        #expect(!FileManager.default.fileExists(atPath: stateFile.path))
        #expect(try Data(contentsOf: legacyFile) == original)
    }

    @Test func releaseBuildsIgnoreTheUITestReset() {
        #if !DEBUG
        #expect(!AppModel.launchedForUITestReset)
        #endif
    }

    @Test func deleteAllRemovesKeptCopiesOldStoreAndExports() throws {
        try writeLegacyStore()
        let model = makeModel()
        model.load()
        let store = StateStore(directory: storeDirectory)
        try Data("{old".utf8).write(to: storeDirectory.appendingPathComponent("state.corrupt.1.json"))
        // As if Aurora had stopped mid-save: a full copy of the records.
        let orphan = storeDirectory.appendingPathComponent("state.json.saving-ABC")
        try Data(contentsOf: stateFile).write(to: orphan)
        let export = try CSVFile(name: "aurora-test.csv", text: "a,b\n").write()
        #expect(FileManager.default.fileExists(atPath: export.path))

        model.deleteAllData()
        #expect(model.deletionResult == .completed)
        #expect(model.state.doses.isEmpty)
        #expect(try savedState().doses.isEmpty)
        #expect(store.corruptBackups().isEmpty)
        #expect(store.orphanedSaves().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: mmkv.path))
        #expect(!FileManager.default.fileExists(atPath: CSVFile.exportDirectory.path))

        // Nothing comes back from the old store on relaunch.
        let relaunched = makeModel()
        relaunched.load()
        #expect(relaunched.state.doses.isEmpty)
    }

    @Test func walkthroughResumesAfterRelaunchAndLocksLinks() {
        let model = makeModel()
        model.load()
        model.completeOnboarding()
        for _ in 0..<4 { model.advanceWalkthrough() }

        let relaunched = makeModel()
        relaunched.load()
        let state = relaunched.state
        #expect(state.isWalkthroughPending)
        #expect(state.onboarding.appWalkthroughStep == 4)
        // Step 5 is on Sleep; a link elsewhere lands on the step's tab.
        #expect(DeepLink.tab(.insights).resolved(walkthroughPending: true, step: 4) == .tab(Walkthrough.tab(forStep: 4)))

        for _ in 0..<20 { relaunched.advanceWalkthrough() }
        #expect(relaunched.state.onboarding.appWalkthroughStep == 9)
        relaunched.completeWalkthrough()
        let finished = makeModel()
        finished.load()
        #expect(!finished.state.isWalkthroughPending)
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
}

/// These run alongside the main-actor suite, whose Delete All test uses the
/// shared export folder, so each writes into its own folder instead.
@Suite struct CSVExportTests {
    final class Calls: @unchecked Sendable { var count = 0 }

    let folder: URL

    init() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("aurora-csv-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func textIsBuiltOnlyWhenShared() throws {
        let calls = Calls()
        let file = CSVFile(name: "aurora-lazy.csv") {
            calls.count += 1
            return "date,mg\n"
        }
        // Settings creates these on every draw; nothing is built yet.
        #expect(calls.count == 0)
        let url = try file.write(to: folder)
        #expect(calls.count == 1)
        #expect(try String(contentsOf: url, encoding: .utf8) == "date,mg\n")
        try FileManager.default.removeItem(at: folder)
    }

    @Test func ancientEntriesExportWithoutFillingEveryDay() throws {
        // A fixed instant (2026-09-27 16:41 UTC) keeps this deterministic.
        let now: Millis = 1_790_527_260_000
        let doses = [Dose(id: "a", timestamp: -8.64e15, mg: 50), Dose(id: "b", timestamp: now - 60_000, mg: 95)]
        let clock = LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let file = CSVFile(name: "aurora-daily-test.csv") {
            Export.dailyTotalsCSV(Export.dailyTotalRows(doses, now: now, clock: clock))
        }
        let text = try String(contentsOf: try file.write(to: folder), encoding: .utf8)
        #expect(text.split(separator: "\n").count == 3)
        try FileManager.default.removeItem(at: folder)
    }
}

@Suite struct HealthAccessTests {
    @Test func requestsReadOnlySleepAccess() {
        #expect(HealthKitService.shareTypes.isEmpty)
        #expect(HealthKitService.readTypes == [HKCategoryType(.sleepAnalysis)])
    }

    @Test func usageTextSaysHealthIsReadOnly() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect((info["NSHealthUpdateUsageDescription"] as? String)?.contains("does not write") == true)
    }
}
