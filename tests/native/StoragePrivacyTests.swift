import Foundation

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  if try !condition() { throw NSError(domain: message, code: 1) }
}
let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try manager.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: root) }
let fresh = root.appendingPathComponent("fresh")
let directory = try StoragePrivacy.prepareMMKV(in: fresh)
try expect(manager.fileExists(atPath: directory.path), "creates storage directory")
try expect(directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, "excludes storage from backup")
print("PASS fresh directory created and exclusion read back")
let payload = Data("existing user records".utf8)
let dataFile = directory.appendingPathComponent("aurora-storage")
try payload.write(to: dataFile)
_ = try StoragePrivacy.prepareMMKV(in: fresh)
try expect(Data(contentsOf: dataFile) == payload, "preserves existing records")
print("PASS repeated startup preserves existing records")
let legacyDocuments = root.appendingPathComponent("legacy")
let legacyDirectory = legacyDocuments.appendingPathComponent("mmkv")
try manager.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
let legacyFile = legacyDirectory.appendingPathComponent("aurora-storage")
try payload.write(to: legacyFile)
try expect(legacyDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup != true, "legacy directory initially included in backups")
let upgraded = try StoragePrivacy.prepareMMKV(in: legacyDocuments)
try expect(upgraded.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, "excludes existing directory")
try expect(Data(contentsOf: legacyFile) == payload, "preserves legacy records")
print("PASS existing unprotected directory excluded without changing records")
let collision = root.appendingPathComponent("collision")
try manager.createDirectory(at: collision, withIntermediateDirectories: true)
try payload.write(to: collision.appendingPathComponent("mmkv"))
do {
  _ = try StoragePrivacy.prepareMMKV(in: collision)
  throw NSError(domain: "must reject file in place of directory", code: 1)
} catch let error as StoragePrivacy.Failure {
  try expect(error == .notDirectory, "reports invalid directory")
}
try expect(Data(contentsOf: collision.appendingPathComponent("mmkv")) == payload, "preserves colliding data")
print("PASS invalid directory fails without deleting data")
enum Simulated: Error { case failure }
do {
  _ = try StoragePrivacy.prepareMMKV(in: root.appendingPathComponent("write-failure"), exclude: { _ in throw Simulated.failure })
  throw NSError(domain: "must propagate exclusion failure", code: 1)
} catch Simulated.failure { print("PASS exclusion error propagates to launch gate") }
do {
  _ = try StoragePrivacy.prepareMMKV(in: root.appendingPathComponent("readback-failure"), exclude: { _ in })
  throw NSError(domain: "must verify exclusion", code: 1)
} catch let error as StoragePrivacy.Failure {
  try expect(error == .backupExclusionNotConfirmed, "reports failed verification")
  print("PASS missing exclusion readback fails closed")
}
