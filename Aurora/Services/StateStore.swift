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
    /// Temporary saves. One is left behind only if Aurora stops mid-save, and
    /// it can hold a full copy of the records.
    var savingPrefix: String { "state.json.saving-" }

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

    /// Writes the state to a temporary file beside `state.json`, reads that
    /// back and checks it decodes to the same state, and only then swaps it
    /// in with one atomic rename. A failed or mismatched write leaves the
    /// previous `state.json` exactly as it was. The read-back checks what the
    /// file system returns; it does not force the bytes to storage (no fsync).
    func save(_ state: AppState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        let manager = FileManager.default
        let temporary = directory.appendingPathComponent("\(savingPrefix)\(UUID().uuidString)")
        defer { try? manager.removeItem(at: temporary) }
        try data.write(to: temporary, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
        try afterTemporaryWrite(temporary)
        let written = try Data(contentsOf: temporary)
        guard written == data, (try? JSONDecoder().decode(AppState.self, from: written)) == state else {
            throw SaveFailure.verificationFailed
        }
        if manager.fileExists(atPath: fileURL.path) {
            _ = try manager.replaceItemAt(fileURL, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: fileURL)
        }
    }

    /// Copies kept aside from files that didn't decode.
    func corruptBackups() -> [URL] {
        files(withPrefix: backupPrefix)
    }

    /// Temporary saves left by a save that never finished. Loading leaves
    /// them alone; only Delete All Data removes them.
    func orphanedSaves() -> [URL] {
        files(withPrefix: savingPrefix)
    }

    private func files(withPrefix prefix: String) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.sorted().map { directory.appendingPathComponent($0) }
    }

    /// Removes every kept copy and unfinished save, and the saved state too
    /// when asked. Used only
    /// by Delete All Data, after the person confirms, and by the DEBUG
    /// UI-test reset.
    func purge(includingState: Bool) throws {
        let manager = FileManager.default
        for url in corruptBackups() + orphanedSaves() + (includingState ? [fileURL] : []) where manager.fileExists(atPath: url.path) {
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
