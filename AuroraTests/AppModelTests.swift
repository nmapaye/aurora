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

    private func makeModel() -> AppModel {
        let directory = storeDirectory
        let docs = documents
        return AppModel(
            clock: LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!),
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
        #expect(!FileManager.default.fileExists(atPath: mmkv.path))

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

    @Test func corruptStateIsMovedAside() throws {
        try StateStore(directory: storeDirectory).prepare()
        try Data("{oops".utf8).write(to: storeDirectory.appendingPathComponent("state.json"))
        let model = makeModel()
        model.load()
        #expect(model.phase == .ready)
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
}
