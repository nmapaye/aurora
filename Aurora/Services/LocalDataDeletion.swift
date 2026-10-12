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
    var clearNotifications: () -> Void = {
        let ids = [CutoffReminder.identifier, "aurora.assistant.briefing"]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundRefresh.identifier)
    }
    var removeFile: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }

    var marker: URL { store.directory.appendingPathComponent("erase.pending") }
    var pending: Bool { FileManager.default.fileExists(atPath: marker.path) }

    func begin() throws {
        try store.prepare()
        try Data("Aurora local erase v1".utf8).write(to: marker, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func finish() throws {
        guard pending else { return }
        // Failures retain the marker. Never restore copies of erased health data.
        try perform("account connections", clearConnections)
        clearNotifications()
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

    static func owns(_ name: String) -> Bool {
        ["state.json", "state.pre-assistant.json", StateMigration.v1SourceFileName, "conversation.json", "conversation.v1-source.json"].contains(name)
            || (name.hasPrefix(StateStore.backupPrefix) && name.hasSuffix(".json"))
            || name.hasPrefix(StateStore.savingPrefix)
            || (name.hasPrefix("conversation.corrupt.") && name.hasSuffix(".json"))
    }
}
