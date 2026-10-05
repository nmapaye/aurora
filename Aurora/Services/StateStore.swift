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

    /// `nil` when nothing has been saved yet. A file that no longer decodes is
    /// moved aside, never overwritten, and reported as `nil`.
    func load(now: Date = .now) -> AppState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(AppState.self, from: data)
        } catch {
            let stamp = Int(now.timeIntervalSince1970 * 1000)
            let backup = directory.appendingPathComponent("state.corrupt.\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return nil
        }
    }

    func save(_ state: AppState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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
