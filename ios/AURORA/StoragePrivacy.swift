import Foundation

/// MMKV v3 uses Documents/mmkv on iOS. Prepare it before the native bridge can
/// open persisted Health records. Recheck on every launch without replacing data.
enum StoragePrivacy {
  enum Failure: Error { case notDirectory, backupExclusionNotConfirmed }

  @discardableResult
  static func prepareMMKV(
    in documents: URL,
    exclude: (URL) throws -> Void = excludeFromBackup
  ) throws -> URL {
    var directory = documents.appendingPathComponent("mmkv", isDirectory: true)
    let manager = FileManager.default
    var isDirectory: ObjCBool = false
    if manager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
      guard isDirectory.boolValue else { throw Failure.notDirectory }
    } else {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try exclude(directory)
    directory.removeAllCachedResourceValues()
    guard try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
      throw Failure.backupExclusionNotConfirmed
    }
    return directory
  }

  private static func excludeFromBackup(_ directory: URL) throws {
    var directory = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
  }
}
