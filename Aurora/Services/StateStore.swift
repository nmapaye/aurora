import AuroraCore
import Foundation

/// Saves Aurora's whole state as one JSON file in Application Support. The
/// folder is excluded from device backups, and nothing is read or written
/// until that exclusion is confirmed, as the React Native build required for
/// its MMKV folder.
struct StateStore {
    enum Failure: Error {
        case notDirectory
        case backupExclusionNotConfirmed
    }

    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("state.json") }

    static func live() throws -> StateStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return StateStore(directory: support.appendingPathComponent("Aurora", isDirectory: true))
    }

    /// Creates the folder if needed and confirms it is excluded from backups.
    func prepare() throws {
        try Self.prepareExcludedDirectory(directory)
    }

    static func prepareExcludedDirectory(_ url: URL) throws {
        var directory = url
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw Failure.notDirectory }
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        directory.removeAllCachedResourceValues()
        guard try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
            throw Failure.backupExclusionNotConfirmed
        }
    }

    enum LoadResult {
        /// Nothing saved yet.
        case missing
        case loaded(AppState)
        /// The file exists but couldn't be read, for example while the
        /// device is locked before its first unlock. Nothing is changed.
        case unreadable
        /// The file was read but doesn't decode. It stays in place, and a
        /// copy is kept beside it when the copy succeeds.
        case corrupt(backup: URL?)
    }

    enum SaveFailure: Error, Equatable {
        /// The file written back doesn't decode to the state that was saved.
        case verificationFailed
    }

    var backupPrefix: String { "state.corrupt." }

    func load(now: Date = .now) -> LoadResult {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return .missing }
        guard let data = try? Data(contentsOf: fileURL) else { return .unreadable }
        if let state = try? JSONDecoder().decode(AppState.self, from: data) {
            return .loaded(state)
        }
        // Retrying shouldn't pile up copies of the same damaged file.
        if let existing = corruptBackups().first(where: { (try? Data(contentsOf: $0)) == data }) {
            return .corrupt(backup: existing)
        }
        let stamp = Int(now.timeIntervalSince1970 * 1000)
        let backup = directory.appendingPathComponent("\(backupPrefix)\(stamp).json")
        do {
            try manager.copyItem(at: fileURL, to: backup)
            return .corrupt(backup: backup)
        } catch {
            return .corrupt(backup: nil)
        }
    }

    /// Writes the state, then reads the file back and checks it decodes to
    /// the same state, so a save is only reported once it is on disk.
    func save(_ state: AppState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let written = try Data(contentsOf: fileURL)
        guard (try? JSONDecoder().decode(AppState.self, from: written)) == state else {
            throw SaveFailure.verificationFailed
        }
    }

    /// Copies kept aside from files that didn't decode.
    func corruptBackups() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix(backupPrefix) }.sorted().map { directory.appendingPathComponent($0) }
    }

    /// Removes every kept copy, and the saved state too when asked. Used only
    /// by Delete All Data, after the person confirms, and by the DEBUG
    /// UI-test reset.
    func purge(includingState: Bool) throws {
        let manager = FileManager.default
        for url in corruptBackups() + (includingState ? [fileURL] : []) where manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
    }
}

/// Carries records over from the React Native build, which kept them in
/// `Documents/mmkv/aurora` under the key `aurora/state`. The old folder is
/// left as it was after a migration: it holds the original blob and any
/// `aurora/state.corrupt.*` backup keys, and `state.json` existing is what
/// marks the migration done.
struct LegacyImport {
    let documents: URL

    static func live() -> LegacyImport? {
        guard let documents = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return nil }
        return LegacyImport(documents: documents)
    }

    var mmkvDirectory: URL { documents.appendingPathComponent("mmkv", isDirectory: true) }
    var mmkvFile: URL { mmkvDirectory.appendingPathComponent("aurora") }

    var hasLegacyData: Bool { FileManager.default.fileExists(atPath: mmkvFile.path) }

    enum Outcome: Equatable {
        case none
        case imported(AppState)
        /// The old file exists but couldn't be read. It is left in place.
        case unreadable
    }

    func read(now: Millis) -> Outcome {
        guard hasLegacyData else { return .none }
        guard let reader = try? MMKVReader(contentsOf: mmkvFile) else { return .unreadable }
        // An empty store, or one whose only value was cleared, has nothing to carry over.
        guard let raw = reader.string(forKey: "aurora/state"), !raw.isEmpty else { return .none }
        guard let state = try? LegacyState.decode(raw, now: now) else { return .unreadable }
        return .imported(state)
    }

    /// Removes the old store, including the backup keys the React Native
    /// build kept beside its state. Ordinary migration never calls this; it
    /// runs only for Delete All Data, after the person confirms.
    func purge() throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: mmkvDirectory.path) {
            try manager.removeItem(at: mmkvDirectory)
        }
    }
}
