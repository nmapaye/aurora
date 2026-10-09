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

    static let protectedFiles = StateMigration.Files(
        read: { try Data(contentsOf: $0) },
        write: { try $0.write(to: $1, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) },
        exists: { FileManager.default.fileExists(atPath: $0.path) }
    )

    /// `nil` when nothing has been saved yet. An older schema is migrated with
    /// its original kept as `state.v1-source.json`. A file that no longer
    /// decodes is copied aside, never overwritten; a file from a newer build
    /// and a migration that can't be verified leave the original in place.
    func load(now: Date = .now) throws -> AppState? {
        let loaded: StateMigration.Loaded?
        do {
            loaded = try StateMigration.load(directory: directory, files: Self.protectedFiles)
        } catch StateMigration.Failure.undecodable {
            let stamp = Int(now.timeIntervalSince1970 * 1000)
            let backup = directory.appendingPathComponent("state.corrupt.\(stamp).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
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
        return loaded.state
    }

    func save(_ state: AppState) throws {
        try StateMigration.encode(state).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Carries records over from the React Native build, which kept them in
/// `Documents/mmkv/aurora` under the key `aurora/state`.
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

    enum Outcome {
        case none
        case imported(AppState)
        /// The old file exists but couldn't be read. It is left in place.
        case unreadable
    }

    func read(now: Millis) -> Outcome {
        guard hasLegacyData else { return .none }
        guard let reader = try? MMKVReader(contentsOf: mmkvFile),
              let raw = reader.string(forKey: "aurora/state") else { return .unreadable }
        guard let state = try? LegacyState.decode(raw, now: now) else { return .unreadable }
        return .imported(state)
    }

    /// Removes the old store once its records are saved in the new one.
    func removeLegacyStore() {
        try? FileManager.default.removeItem(at: mmkvDirectory)
    }
}
