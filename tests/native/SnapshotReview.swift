import Foundation

@main
struct SnapshotReview {
  static func check(_ value: Bool, _ message: String) {
    if !value { fatalError(message) }
  }
  static func main() throws {
    let now = ISO8601DateFormatter().date(from: "2026-09-07T12:00:00Z")!
    let milliseconds = now.timeIntervalSince1970 * 1000
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    var payload: [String: Any] = [
      "version": 1, "generatedAt": milliseconds, "expiresAt": milliseconds + 900000,
      "localDay": formatter.string(from: now), "timezoneOffsetMinutes": -TimeZone.current.secondsFromGMT(for: now) / 60, "loggedMg": NSNull(), "activeMg": 12.5,
      "nextBedtime": milliseconds + 3600000, "cutoff": milliseconds + 1800000,
      "showLockValues": false, "drinks": [["id": "espresso", "name": "Espresso", "mg": 60]],
    ]
    func decode() throws -> AuroraSnapshot {
      try JSONDecoder().decode(AuroraSnapshot.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    let valid = try decode()
    check(valid.loggedMg == nil && valid.activeMg == 12.5, "Missing intake and modeled residual must remain distinct")
    check(valid.drinks.first?.mg == 60 && !valid.showLockValues, "Drink and privacy fields must decode")
    check(valid.isFresh(at: now), "Snapshot should be fresh at generation")
    check(valid.isFresh(at: now.addingTimeInterval(899.999)), "Snapshot should remain fresh before expiry")
    check(!valid.isFresh(at: now.addingTimeInterval(900)), "Snapshot must expire at the boundary")
    check(!valid.isFresh(at: now.addingTimeInterval(-1)), "Future generated snapshots must not appear fresh")
    check(AuroraShared.date(milliseconds) == now, "Milliseconds must convert exactly to seconds")
    payload["version"] = 2
    check(!(try decode()).isFresh(at: now), "Unsupported versions must not appear fresh")
    payload["version"] = 1
    payload["timezoneOffsetMinutes"] = -TimeZone.current.secondsFromGMT(for: now) / 60 + 60
    check(!(try decode()).isFresh(at: now), "A timezone change must invalidate the snapshot")
    payload["timezoneOffsetMinutes"] = -TimeZone.current.secondsFromGMT(for: now) / 60
    payload["localDay"] = "2026-09-06"
    check(!(try decode()).isFresh(at: now), "A snapshot from another local day must not appear fresh")
    print("Snapshot Codable and freshness checks passed (Foundation-only, not an iOS build).")
  }
}
