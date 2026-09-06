import Foundation

struct AuroraDrink: Codable, Hashable { let id: String; let name: String; let mg: Int }
struct AuroraSnapshot: Codable {
  let version: Int
  let generatedAt: Double
  let expiresAt: Double
  let localDay: String
  let timezoneOffsetMinutes: Int
  let loggedMg: Double?
  let activeMg: Double?
  let nextBedtime: Double?
  let cutoff: Double?
  let showLockValues: Bool
  let drinks: [AuroraDrink]
  func isFresh(at date: Date = Date()) -> Bool {
    let now = date.timeIntervalSince1970 * 1000
    let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
    return version == 1 && timezoneOffsetMinutes == -TimeZone.current.secondsFromGMT(for:date) / 60 && now >= generatedAt && now < expiresAt && formatter.string(from: date) == localDay
  }
}
enum AuroraShared {
  static let group = "group.com.nmapaye.aurora.shared"
  static let key = "snapshot-v1"
  static func read() -> AuroraSnapshot? {
    guard let data = UserDefaults(suiteName: group)?.data(forKey: key),
      let snapshot = try? JSONDecoder().decode(AuroraSnapshot.self, from: data), snapshot.version == 1 else { return nil }
    return snapshot
  }
  static func date(_ milliseconds: Double) -> Date { Date(timeIntervalSince1970: milliseconds / 1000) }
}

// Separate atomic files prevent a foreground reader from losing an intent that
// arrives concurrently. JavaScript acknowledges only after durable enqueue.
enum AuroraInbox {
  static func directory() throws -> URL {
    guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AuroraShared.group) else { throw CocoaError(.fileNoSuchFile) }
    let directory = group.appendingPathComponent("pending-actions",isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    return directory
  }
  static func pending() -> [[String:String]] {
    guard let directory = try? directory(), let files = try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) else { return [] }
    return files.sorted{$0.lastPathComponent < $1.lastPathComponent}.compactMap { file in
      guard file.pathExtension == "txt", let url = try? String(contentsOf:file,encoding:.utf8) else {return nil}
      return ["id":file.lastPathComponent,"url":url]
    }
  }
  static func append(_ url: String) throws {
    guard pending().count < 20 else { throw CocoaError(.fileWriteOutOfSpace) }
    let id = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).txt"
    try Data(url.utf8).write(to:directory().appendingPathComponent(id),options:.atomic)
  }
  static func acknowledge(_ id:String) throws {
    guard !id.contains("/"), !id.contains(".."), id.hasSuffix(".txt") else { return }
    try FileManager.default.removeItem(at:directory().appendingPathComponent(id))
  }
  static func clear() { for item in pending() { if let id=item["id"] {try? acknowledge(id)} } }
}
