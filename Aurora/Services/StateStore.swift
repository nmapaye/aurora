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
        case invalidState
        /// Written by a newer build. The file is left as it is.
        case unsupportedVersion
        case verificationFailed
        /// Something other than a file sits where `state.json` belongs.
        case stateIsNotAFile
    }

    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("state.json") }
    /// Runs between writing the temporary file and checking it. Tests use it
    /// to damage the write; the app leaves it empty.
    var afterTemporaryWrite: (URL) throws -> Void = { _ in }

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

    static let protectedFiles = StateMigration.Files(
        read: { try Data(contentsOf: $0) },
        write: { try $0.write(to: $1, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) },
        exists: { FileManager.default.fileExists(atPath: $0.path) }
    )

    static let backupPrefix = "state.corrupt."
    /// Temporary saves. One is left behind only if Aurora stops mid-save, and
    /// it can hold a full copy of the records. Erase removes them.
    static let savingPrefix = "state.json.saving-"

    /// `nil` when nothing has been saved yet. An older schema is migrated with
    /// its original kept as `state.v1-source.json`. A file that no longer
    /// decodes is copied aside, never overwritten; a file from a newer build
    /// and a migration that can't be verified leave the original in place.
    /// Records with no calendar date are dropped only once the file as found
    /// has a copy kept beside it; without one, loading fails and nothing is
    /// written.
    func load(now: Date = .now) throws -> AppState? {
        let loaded: StateMigration.Loaded?
        do {
            loaded = try StateMigration.load(directory: directory, files: Self.protectedFiles)
        } catch StateMigration.Failure.undecodable {
            if let data = try? Data(contentsOf: fileURL) { _ = keepCopy(of: data, now: now) }
            throw Failure.invalidState
        } catch StateMigration.Failure.unsupportedVersion {
            throw Failure.unsupportedVersion
        } catch {
            throw Failure.verificationFailed
        }
        guard let loaded else { return nil }
        let snapshot = directory.appendingPathComponent("state.pre-assistant.json")
        if !FileManager.default.fileExists(atPath: snapshot.path) {
            try loaded.original.write(to: snapshot, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        let cleaned = loaded.state.droppingInvalidTimes()
        guard cleaned != loaded.state else { return loaded.state }
        guard keepCopy(of: loaded.original, now: now) != nil else { throw Failure.invalidState }
        return cleaned
    }

    /// Copies `data` (the current state.json) aside, reusing an identical
    /// copy so retries don't pile them up. `nil` if the copy failed.
    private func keepCopy(of data: Data, now: Date) -> URL? {
        if let existing = corruptBackups().first(where: { (try? Data(contentsOf: $0)) == data }) {
            return existing
        }
        let stamp = Int(now.timeIntervalSince1970 * 1000)
        let backup = directory.appendingPathComponent("\(Self.backupPrefix)\(stamp).json")
        do {
            try data.write(to: backup, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
            return backup
        } catch {
            return nil
        }
    }

    /// Writes the state to a temporary file beside `state.json`, reads that
    /// back and checks it decodes to the same state, and only then swaps it
    /// in with one atomic rename. A failed or mismatched write leaves the
    /// previous `state.json` exactly as it was. The read-back checks what the
    /// file system returns; it does not force the bytes to storage (no fsync).
    func save(_ state: AppState) throws {
        let data = try StateMigration.encode(state)
        let manager = FileManager.default
        let temporary = directory.appendingPathComponent("\(Self.savingPrefix)\(UUID().uuidString)")
        defer { try? manager.removeItem(at: temporary) }
        try data.write(to: temporary, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
        try afterTemporaryWrite(temporary)
        let written = try Data(contentsOf: temporary)
        guard written == data, (try? StateMigration.decode(written)) == state else {
            throw Failure.verificationFailed
        }
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) {
            // Never swap a file in over something that isn't one.
            guard !isDirectory.boolValue else { throw Failure.stateIsNotAFile }
            _ = try manager.replaceItemAt(fileURL, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: fileURL)
        }
    }

    /// Copies kept aside from files that didn't decode.
    func corruptBackups() -> [URL] {
        files(withPrefix: Self.backupPrefix)
    }

    /// Temporary saves left by a save that never finished. Loading leaves
    /// them alone; only erase removes them.
    func orphanedSaves() -> [URL] {
        files(withPrefix: Self.savingPrefix)
    }

    private func files(withPrefix prefix: String) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.sorted().map { directory.appendingPathComponent($0) }
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

    static let stateKey = "aurora/state"
    static let backupKeyPrefix = "aurora/state.corrupt."

    /// `.none` only when the old store holds no state at all: no
    /// `aurora/state` key (or an empty one) and no kept copies. A key that is
    /// present but can't be decoded, or only kept copies of a damaged
    /// state, is `.unreadable`, so nothing is written and the next launch
    /// tries again.
    func read(now: Millis) -> Outcome {
        guard hasLegacyData else { return .none }
        guard let reader = try? MMKVReader(contentsOf: mmkvFile) else { return .unreadable }
        let hasBackups = reader.values.keys.contains { $0.hasPrefix(Self.backupKeyPrefix) }
        guard reader.values[Self.stateKey] != nil else { return hasBackups ? .unreadable : .none }
        guard let raw = reader.string(forKey: Self.stateKey) else { return .unreadable }
        if raw.isEmpty { return hasBackups ? .unreadable : .none }
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
