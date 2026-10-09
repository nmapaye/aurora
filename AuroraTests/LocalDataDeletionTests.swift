import AuroraCore
import Foundation
import Testing
@testable import Aurora

@MainActor
@Suite struct LocalDataDeletionTests {
    @Test func eraseRemovesSnapshotsAndOwnedLegacyFilesButPreservesUnrelatedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: root.appendingPathComponent("Support"))
        let legacy = LegacyImport(documents: root.appendingPathComponent("Documents"))
        try store.prepare()
        try FileManager.default.createDirectory(at: legacy.mmkvDirectory, withIntermediateDirectories: true)
        for name in ["state.json", "state.pre-assistant.json", "state.v1-source.json", "state.corrupt.1.json", "conversation.json", "conversation.v1-source.json", "unrelated.txt"] {
            try Data("private fixture".utf8).write(to: store.directory.appendingPathComponent(name))
        }
        for name in ["aurora", "aurora.crc", "other-store"] {
            try Data("legacy fixture".utf8).write(to: legacy.mmkvDirectory.appendingPathComponent(name))
        }
        var connectionsCleared = false
        var notificationsCleared = false
        let deletion = LocalDataDeletion(store: store, legacy: legacy,
            clearConnections: { connectionsCleared = true }, clearNotifications: { notificationsCleared = true })
        try deletion.begin(); try deletion.finish()
        #expect(connectionsCleared && notificationsCleared)
        #expect(!deletion.pending)
        #expect(try JSONDecoder().decode(AppState.self, from: Data(contentsOf: store.fileURL)) == AppState())
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).sorted() == ["state.json", "unrelated.txt"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: legacy.mmkvDirectory.path) == ["other-store"])
    }

    @Test func failedEraseRetainsIntentAndRetryCompletesWithoutRestoringData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: root)
        try store.prepare()
        try Data("old records".utf8).write(to: store.fileURL)
        var deletion = LocalDataDeletion(store: store, legacy: nil, clearConnections: {}, clearNotifications: {})
        try deletion.begin()
        deletion.removeFile = { _ in throw StateStore.Failure.verificationFailed }
        #expect(throws: LocalDataDeletion.Failure.self) { try deletion.finish() }
        #expect(deletion.pending)
        let retry = LocalDataDeletion(store: store, legacy: nil, clearConnections: {}, clearNotifications: {})
        try retry.finish()
        #expect(!retry.pending)
        #expect(try JSONDecoder().decode(AppState.self, from: Data(contentsOf: store.fileURL)).doses.isEmpty)
    }

    @Test func connectionFailureLeavesMarkerAndOriginalFilesForRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: root); try store.prepare(); try store.save(AppState())
        let deletion = LocalDataDeletion(store: store, legacy: nil,
            clearConnections: { throw CalendarActionError.unavailable }, clearNotifications: {})
        try deletion.begin()
        #expect(throws: LocalDataDeletion.Failure.self) { try deletion.finish() }
        #expect(deletion.pending && FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func actualSimulatorConnectionsAndNotificationsAllowAnEmptyErase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: root)
        let deletion = LocalDataDeletion(store: store, legacy: nil)
        try deletion.begin(); try deletion.finish()
        #expect(!deletion.pending)
        #expect(try JSONDecoder().decode(AppState.self, from: Data(contentsOf: store.fileURL)) == AppState())
    }

    @Test func pendingEraseCompletesBeforeRelaunchCanImportLegacyRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: root.appendingPathComponent("Support"))
        let legacy = LegacyImport(documents: root.appendingPathComponent("Documents"))
        try store.prepare()
        var old = AppState(); old.onboarding.completed = true
        try store.save(old)
        try FileManager.default.createDirectory(at: legacy.mmkvDirectory, withIntermediateDirectories: true)
        try Data("retained legacy fixture".utf8).write(to: legacy.mmkvFile)
        let deletion = LocalDataDeletion(store: store, legacy: legacy, clearConnections: {}, clearNotifications: {})
        try deletion.begin()
        let model = AppModel(makeStore: { store }, legacy: { legacy }, makeDeletion: {
            LocalDataDeletion(store: $0, legacy: $1, clearConnections: {}, clearNotifications: {})
        })
        model.load()
        #expect(model.phase == .ready && model.state == AppState())
        #expect(!deletion.pending && !legacy.hasLegacyData)
    }

    @Test func pendingEraseFailureBlocksRecordsAndReportsTheStage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: root); try store.prepare()
        var old = AppState(); old.onboarding.completed = true; try store.save(old)
        try LocalDataDeletion(store: store, legacy: nil).begin()
        let model = AppModel(makeStore: { store }, legacy: { nil }, makeDeletion: {
            LocalDataDeletion(store: $0, legacy: $1, clearConnections: {
                throw GoogleCalendarProvider.CredentialDeletionFailure(status: -34018)
            }, clearNotifications: {})
        })
        model.load()
        #expect(model.phase == .storageUnavailable && !model.state.onboarding.completed)
        #expect(model.mutationFailure?.contains("account connections") == true)
        #expect(model.mutationFailure?.contains("-34018") == true)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func lateCalendarReadCannotRestoreErasedCommitments() async throws {
        let provider = DelayedCalendarProvider()
        let suite = "aurora-erase-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = CalendarService(providers: [provider], defaults: defaults)
        await service.refreshCalendars()
        service.selected = ["apple:fixture"]
        let read = Task { await service.refresh() }
        while provider.reply == nil { await Task.yield() }
        service.resetAfterErase()
        provider.reply?.resume(returning: [.init(id: "event", calendarID: "fixture", provider: .apple, title: "Private fixture", start: .now, end: .now.addingTimeInterval(600), timeZone: "UTC", revision: "1", canMove: true, recurring: false)])
        await read.value
        #expect(service.commitments.isEmpty && service.selected.isEmpty)
        #expect(defaults.object(forKey: "assistant.selectedCalendars") == nil)
    }
}

@MainActor private final class DelayedCalendarProvider: CommitmentProvider {
    let providerID = CalendarProviderID.apple
    var reply: CheckedContinuation<[Commitment], Never>?
    func calendars() async throws -> [AssistantCalendar] { [.init(id: "fixture", provider: .apple, title: "Fixture", writable: true)] }
    func events(calendarIDs: [String], from: Date, to: Date) async throws -> [Commitment] {
        await withCheckedContinuation { reply = $0 }
    }
    func current(_ event: Commitment) async throws -> Commitment { event }
    func move(_ change: CalendarChange) async throws -> Commitment { throw CalendarActionError.unavailable }
}
