import Foundation

/// Opens `state.json`, migrating an older schema in place. Migration is
/// conservative: the original bytes are first kept as
/// `state.v1-source.json` and read back, the migrated value is checked
/// against the source, and only then is the new file written and read back.
/// Any failure leaves the original `state.json` as it was, so a retry starts
/// over safely; if putting it back can't be confirmed, the failure is
/// `restoreFailed` and the retained source stays. Files from a newer build,
/// or that don't decode, are never rewritten.
public enum StateMigration {
    public static let stateFileName = "state.json"
    public static let v1SourceFileName = "state.v1-source.json"

    public enum Failure: Error, Equatable, Sendable {
        case undecodable
        /// Written by a newer build. Left untouched.
        case unsupportedVersion(Int)
        /// A retained source exists with different contents. Neither file is
        /// changed, so nothing that might be the only copy is replaced.
        case retainedSourceMismatch
        case verificationFailed(String)
        /// Saving the migrated file failed and `state.json` couldn't be put
        /// back byte for byte. The verified `state.v1-source.json` is left in
        /// place as the copy to recover from.
        case restoreFailed(String)
    }

    /// File access, injected so the app can add file protection and tests
    /// can fail a write.
    public struct Files: Sendable {
        public var read: @Sendable (URL) throws -> Data
        public var write: @Sendable (Data, URL) throws -> Void
        public var exists: @Sendable (URL) -> Bool

        public init(
            read: @escaping @Sendable (URL) throws -> Data,
            write: @escaping @Sendable (Data, URL) throws -> Void,
            exists: @escaping @Sendable (URL) -> Bool
        ) {
            self.read = read
            self.write = write
            self.exists = exists
        }

        public static let standard = Files(
            read: { try Data(contentsOf: $0) },
            write: { try $0.write(to: $1, options: .atomic) },
            exists: { FileManager.default.fileExists(atPath: $0.path) }
        )
    }

    public struct Loaded: Equatable, Sendable {
        public var state: AppState
        /// The bytes `state.json` held when opened.
        public var original: Data
        /// The version migrated from, or nil when the file was current.
        public var migratedFrom: Int?
    }

    private struct Header: Decodable {
        var schemaVersion: Int?
    }

    public static func encode(_ state: AppState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }

    /// The stored version, checked before anything else is decoded so a newer
    /// file fails as unsupported rather than as corrupt. A file without one
    /// predates version 2.
    public static func storedVersion(_ data: Data) throws -> Int {
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: data) } catch { throw Failure.undecodable }
        let version = header.schemaVersion ?? 1
        guard version <= AppState.schemaVersion else { throw Failure.unsupportedVersion(version) }
        return version
    }

    public static func decode(_ data: Data) throws -> AppState {
        _ = try storedVersion(data)
        do { return try JSONDecoder().decode(AppState.self, from: data) } catch { throw Failure.undecodable }
    }

    /// Version 1 to 2 adds fields that default empty; every record and
    /// setting carries over unchanged.
    public static func migrate(_ state: AppState) -> AppState {
        var migrated = state
        migrated.schemaVersion = AppState.schemaVersion
        return migrated
    }

    /// Everything a version-1 file holds, compared field by field.
    static func carriesOver(_ source: AppState, to migrated: AppState) -> Bool {
        source.doses.count == migrated.doses.count && source.doses == migrated.doses
            && source.sleeps.count == migrated.sleeps.count && source.sleeps == migrated.sleeps
            && source.vigilanceSessions.count == migrated.vigilanceSessions.count && source.vigilanceSessions == migrated.vigilanceSessions
            && source.energyCheckIns == migrated.energyCheckIns
            && source.prefs == migrated.prefs
            && source.onboarding == migrated.onboarding
            && source.healthSync == migrated.healthSync
            && source.demoMode == migrated.demoMode
            && source.appearanceMode == migrated.appearanceMode
    }

    public static func load(directory: URL, files: Files = .standard) throws -> Loaded? {
        let stateURL = directory.appendingPathComponent(stateFileName)
        guard files.exists(stateURL) else { return nil }
        let original = try files.read(stateURL)
        let version = try storedVersion(original)
        let state = try decode(original)
        guard version < AppState.schemaVersion else {
            return Loaded(state: state, original: original, migratedFrom: nil)
        }

        let sourceURL = directory.appendingPathComponent(v1SourceFileName)
        if files.exists(sourceURL) {
            guard try files.read(sourceURL) == original else { throw Failure.retainedSourceMismatch }
        } else {
            try files.write(original, sourceURL)
        }
        let retained = try files.read(sourceURL)
        guard retained == original, try decode(retained) == state else {
            throw Failure.verificationFailed("retained source")
        }

        let migrated = migrate(state)
        let encoded = try encode(migrated)
        guard carriesOver(state, to: migrated), try decode(encoded) == migrated else {
            throw Failure.verificationFailed("migrated records")
        }
        do {
            try files.write(encoded, stateURL)
            guard try decode(files.read(stateURL)) == migrated else { throw Failure.verificationFailed("saved state") }
        } catch {
            try restoreOriginal(original, at: stateURL, sourceURL: sourceURL, files: files, after: error)
            throw error
        }
        return Loaded(state: migrated, original: original, migratedFrom: version)
    }

    /// Puts the original bytes back after a failed save and reads them back.
    /// Never touches the retained source; if the restore can't be confirmed,
    /// says so instead of reporting only the save failure.
    private static func restoreOriginal(_ original: Data, at stateURL: URL, sourceURL: URL, files: Files, after error: Error) throws {
        do {
            try files.write(original, stateURL)
            guard try files.read(stateURL) == original else { throw Failure.verificationFailed("restored state") }
        } catch let restoreError {
            let sourceKept = (try? files.read(sourceURL)) == original
            throw Failure.restoreFailed(
                "save: \(error); restore: \(restoreError); retained source \(sourceKept ? "verified" : "unverified")"
            )
        }
    }
}
