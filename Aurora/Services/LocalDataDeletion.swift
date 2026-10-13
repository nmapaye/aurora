import AuroraCore
import BackgroundTasks
import Foundation
import UserNotifications

/// A durable erase intent is written before deletion. Interrupted erases resume
/// before records or retained migration sources can be loaded again.
@MainActor
struct LocalDataDeletion {
    struct Failure: LocalizedError {
        let stage: String
        let underlying: Error
        var errorDescription: String? { "Erase failed during \(stage): \(underlying.localizedDescription)" }
    }
    private func perform<T>(_ stage: String, _ action: () throws -> T) throws -> T {
        do { return try action() } catch { throw Failure(stage: stage, underlying: error) }
    }
    let store: StateStore
    let legacy: LegacyImport?
    var clearConnections: () throws -> Void = {
        try GoogleCalendarProvider.deleteLocalCredentials()
        UserDefaults.standard.removeObject(forKey: "assistant.selectedCalendars")
        UserDefaults.standard.removeObject(forKey: "assistant.calendarMirrorAuthority")
    }
    /// Every notification Aurora schedules: the daily cutoff reminder, a
    /// saved cutoff scenario reminder, and the morning briefing.
    static let notificationIdentifiers = [CutoffReminder.identifier, CutoffScenario.reminderIdentifier, "aurora.assistant.briefing"]
    /// Wake reminders carry one id per day and offset, so they go by prefix.
    static let notificationPrefixes = [WakeReminders.identifierPrefix]
    /// Queues the removals on the notification queue and calls `done` once
    /// they have run. Removal is a synchronous XPC call that stalled the main
    /// thread for minutes on a fresh simulator, so nothing here waits on it.
    var clearNotifications: (_ done: @escaping @Sendable () -> Void) -> Void = { done in
        UserDefaults.standard.removeObject(forKey: ReminderService.wakeScheduleKey)
        LiveNotificationBackend.removeAll(ids: LocalDataDeletion.notificationIdentifiers, prefixes: LocalDataDeletion.notificationPrefixes) {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundRefresh.identifier)
            done()
        }
    }
    var removeFile: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }

    var marker: URL { store.directory.appendingPathComponent("erase.pending") }
    var pending: Bool { FileManager.default.fileExists(atPath: marker.path) }
    /// Written before notification removal is queued and removed once it has
    /// run, so an erase interrupted before then clears them at next launch.
    var notificationsMarker: URL { store.directory.appendingPathComponent("erase.notifications.pending") }
    var notificationsPending: Bool { FileManager.default.fileExists(atPath: notificationsMarker.path) }

    func begin() throws {
        try store.prepare()
        try Data("Aurora local erase v1".utf8).write(to: marker, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func finish() throws {
        guard pending else { return }
        // Failures retain the marker. Never restore copies of erased health data.
        try perform("account connections", clearConnections)
        try perform("noting notification removal") {
            try Data("Aurora notification erase v1".utf8).write(to: notificationsMarker, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        clearQueuedNotifications()
        let files = try perform("listing local storage") { try FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil) }
        for file in files where Self.owns(file.lastPathComponent) {
            try perform("removing \(file.lastPathComponent)") { try removeFile(file) }
        }
        if let legacy {
            for name in ["aurora", "aurora.crc"] {
                let file = legacy.mmkvDirectory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: file.path) { try perform("removing \(file.lastPathComponent)") { try removeFile(file) } }
            }
        }
        try perform("removing exported CSV files") { try CSVFile.purgeExports() }
        try perform("writing empty records") { try store.save(AppState()) }
        guard try JSONDecoder().decode(AppState.self, from: Data(contentsOf: store.fileURL)) == AppState() else {
            throw StateStore.Failure.verificationFailed
        }
        try perform("completing erase") { try removeFile(marker) }
    }

    /// Resumes notification removal an earlier erase queued but Aurora
    /// stopped before it ran.
    func resumeNotificationClearing() {
        guard notificationsPending else { return }
        clearQueuedNotifications()
    }

    private func clearQueuedNotifications() {
        let marker = notificationsMarker
        clearNotifications { try? FileManager.default.removeItem(at: marker) }
    }

    static func owns(_ name: String) -> Bool {
        ["state.json", "state.pre-assistant.json", StateMigration.v1SourceFileName, "conversation.json", "conversation.v1-source.json"].contains(name)
            || (name.hasPrefix(StateStore.backupPrefix) && name.hasSuffix(".json"))
            || name.hasPrefix(StateStore.savingPrefix)
            || (name.hasPrefix("conversation.corrupt.") && name.hasSuffix(".json"))
    }
}
