import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// Save and load protections carried over from main's native line: verified
/// saves, undateable records, unfinished saves, the old store's edge cases
/// and lazily built CSV exports.
@MainActor
@Suite struct StateStoreSafetyTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aurora-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private var storeDirectory: URL { root.appendingPathComponent("Support/Aurora", isDirectory: true) }
    private var documents: URL { root.appendingPathComponent("Documents", isDirectory: true) }
    private var stateFile: URL { storeDirectory.appendingPathComponent("state.json") }
    private var legacy: LegacyImport { LegacyImport(documents: documents) }

    private func makeModel(afterTemporaryWrite: @escaping (URL) throws -> Void = { _ in }) -> AppModel {
        let directory = storeDirectory
        let docs = documents
        return AppModel(
            clock: LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!),
            makeStore: { StateStore(directory: directory, afterTemporaryWrite: afterTemporaryWrite) },
            legacy: { LegacyImport(documents: docs) }
        )
    }

    // MARK: Saves

    @Test func aMismatchedWriteLeavesThePreviousStateInPlace() throws {
        let first = makeModel()
        first.load()
        #expect(first.completeOnboarding())
        let good = try Data(contentsOf: stateFile)

        // The temporary file decodes, but to a different state.
        let other = try StateMigration.encode(AppState())
        let model = makeModel(afterTemporaryWrite: { try other.write(to: $0) })
        model.load()
        _ = model.quickAdd(CaffeinePreset.all[0])
        #expect(model.state.doses.isEmpty)
        #expect(model.mutationFailure != nil)
        #expect(try Data(contentsOf: stateFile) == good)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: storeDirectory.path).filter { $0.hasPrefix(StateStore.savingPrefix) }
        #expect(leftovers.isEmpty)
    }

    @Test func aFailedSwapLeavesThePreviousState() throws {
        let first = makeModel()
        first.load()
        #expect(first.completeOnboarding())
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
        #expect(model.mutationFailure != nil)
        #expect(try Data(contentsOf: stateFile) == good)
    }

    @Test func loadingLeavesAnUnfinishedSaveInPlace() throws {
        let first = makeModel()
        first.load()
        #expect(first.completeOnboarding())
        let orphan = storeDirectory.appendingPathComponent("\(StateStore.savingPrefix)XYZ")
        try Data("partial".utf8).write(to: orphan)

        let relaunched = makeModel()
        relaunched.load()
        #expect(relaunched.phase == .ready)
        #expect(try Data(contentsOf: orphan) == Data("partial".utf8))
        #expect(relaunched.quickAdd(CaffeinePreset.all[0]) != nil)
        #expect(relaunched.mutationFailure == nil)
        #expect(FileManager.default.fileExists(atPath: orphan.path))
    }

    // MARK: Undateable records

    @Test func undateableRecordsAreDroppedAtLoadWithACopyKept() throws {
        // As a hand edit could leave it: one ordinary dose, one at 1e300 ms.
        try StateStore(directory: storeDirectory).prepare()
        var edited = AppState()
        edited.onboarding.completed = true
        edited.doses = [
            Dose(id: "ok", timestamp: 1_790_000_000_000, mg: 95),
            Dose(id: "huge", timestamp: 1e300, mg: 60),
        ]
        let original = try StateMigration.encode(edited)
        try original.write(to: stateFile)

        let model = makeModel()
        model.load()
        #expect(model.phase == .ready)
        #expect(model.state.doses.map(\.id) == ["ok"])
        let backups = StateStore(directory: storeDirectory).corruptBackups()
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: backups[0]) == original)
        #expect(!Export.doseEntriesCSV(model.state.doses, clock: model.clock).contains("huge"))

        // The next save writes the cleaned state; relaunching doesn't copy again.
        model.setPrefs { $0.cutoffHour = 13 }
        let relaunched = makeModel()
        relaunched.load()
        #expect(relaunched.state.doses.map(\.id) == ["ok"])
        #expect(StateStore(directory: storeDirectory).corruptBackups().count == 1)
    }

    // MARK: Sleep target without a default

    /// A file from a build that pre-selected 8 h, as it was written.
    private func writeTargetFixture(target: Double, sleepTargetOutcome: String) throws {
        try StateStore(directory: storeDirectory).prepare()
        let file = #"{"schemaVersion":2,"doses":[],"sleeps":[],"vigilanceSessions":[],"energyCheckIns":[],"demoMode":false,"appearanceMode":"system","prefs":{"halfLife":5,"targetSleep":\#(target),"dailyLimitMg":400,"cutoffHour":16,"notifyCutoff":false},"onboarding":{"completed":true,"source":"manual","permissionStatus":"unsupported","appWalkthroughCompleted":true,"appWalkthroughStep":9,"setupStep":7,"setupOutcomes":{"0":"answered","2":"\#(sleepTargetOutcome)"}},"healthSync":{"importedCount":0,"importStatus":"idle"}}"#
        try Data(file.utf8).write(to: stateFile)
    }

    @Test func eightHoursKeptBySkippingSetupLoadsUnsetAndStaysUnset() throws {
        try writeTargetFixture(target: 8, sleepTargetOutcome: "skipped")
        let model = makeModel()
        model.load()
        #expect(model.phase == .ready)
        #expect(model.state.prefs.targetSleep == nil)
        // Nothing else is touched, and no damaged-file copy is made for it.
        #expect(model.state.prefs.cutoffHour == 16 && model.state.onboarding.completed)
        #expect(StateStore(directory: storeDirectory).corruptBackups().isEmpty)

        model.setPrefs { $0.cutoffHour = 13 }
        #expect(String(decoding: try Data(contentsOf: stateFile), as: UTF8.self).contains(#""sleepTargetFormat":1"#))
        let relaunched = makeModel()
        relaunched.load()
        #expect(relaunched.state.prefs.targetSleep == nil)

        // Choosing 8 h afterwards is the person's own and survives relaunch.
        relaunched.setPrefs { $0.targetSleep = 8 }
        let again = makeModel()
        again.load()
        #expect(again.state.prefs.targetSleep == 8)
    }

    @Test func aTargetChosenAtSetupIsKept() throws {
        try writeTargetFixture(target: 8, sleepTargetOutcome: "answered")
        let model = makeModel()
        model.load()
        #expect(model.state.prefs.targetSleep == 8)
    }

    // MARK: Erase

    @Test func eraseRemovesUnfinishedSavesAndExports() throws {
        let store = StateStore(directory: storeDirectory)
        try store.prepare()
        try StateMigration.encode(AppState()).write(to: stateFile)
        // As if Aurora had stopped mid-save: a full copy of the records.
        try Data(contentsOf: stateFile).write(to: storeDirectory.appendingPathComponent("\(StateStore.savingPrefix)ABC"))
        let export = try CSVFile(name: "aurora-erase-test.csv", text: "a,b\n").write()
        #expect(FileManager.default.fileExists(atPath: export.path))

        let deletion = LocalDataDeletion(store: store, legacy: nil, clearConnections: {}, clearNotifications: { $0() })
        try deletion.begin()
        try deletion.finish()
        #expect(store.orphanedSaves().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: CSVFile.exportDirectory.path))
    }

    // MARK: The React Native store

    private func writeRawLegacyStore(_ pairs: [(String, [UInt8])]) throws {
        try FileManager.default.createDirectory(at: legacy.mmkvDirectory, withIntermediateDirectories: true)
        var payload: [UInt8] = [0xFF, 0xFF, 0xFF, 0x07]
        for (key, value) in pairs {
            payload += [UInt8(key.utf8.count)] + Array(key.utf8) + [UInt8(value.count)] + value
        }
        let size = UInt32(payload.count)
        try Data([UInt8(size & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 24 & 0xFF)] + payload)
            .write(to: legacy.mmkvFile)
    }

    @Test func legacyStateThatIsNotUTF8IsUnreadableNotEmpty() throws {
        try writeRawLegacyStore([("aurora/state", [0x02, 0xFF, 0xFE])])
        #expect(legacy.read(now: 0) == .unreadable)
    }

    @Test func legacyStoreWithOnlyKeptCopiesIsUnreadable() throws {
        try FileManager.default.createDirectory(at: legacy.mmkvDirectory, withIntermediateDirectories: true)
        try MMKVReader.encode([(key: "aurora/state.corrupt.1790000000000", value: "{bad")]).write(to: legacy.mmkvFile)
        #expect(legacy.read(now: 0) == .unreadable)
    }

    @Test func emptyLegacyStoreIsNotAFailure() throws {
        try FileManager.default.createDirectory(at: legacy.mmkvDirectory, withIntermediateDirectories: true)
        try MMKVReader.encode([(key: "other", value: "x")]).write(to: legacy.mmkvFile)
        #expect(legacy.read(now: 0) == .none)
        let model = makeModel()
        model.load()
        #expect(model.phase == .ready)
        #expect(!model.legacyImportFailed)
    }
}

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
