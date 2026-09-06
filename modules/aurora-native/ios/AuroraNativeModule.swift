import ExpoModulesCore
import WidgetKit
import ActivityKit

public class AuroraNativeModule: Module {
  public func definition() -> ModuleDefinition {
    Name("AuroraNative")
    Function("pendingRequests") { () -> [[String:String]] in AuroraInbox.pending() }
    Function("acknowledgeRequest") { (id:String) throws in try AuroraInbox.acknowledge(id) }
    Function("clearRequests") { AuroraInbox.clear() }
    Function("availability") { () -> [String: Bool] in
      var live = false
      if #available(iOS 16.2, *) { live = ActivityAuthorizationInfo().areActivitiesEnabled }
      return ["widgets": true, "shortcuts": ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 16, "liveActivities": live]
    }
    Function("writeSnapshot") { (json: String?) throws in
      guard let defaults = UserDefaults(suiteName: AuroraShared.group) else { throw NSError(domain: "Aurora", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group unavailable"]) }
      if let json = json, let data = json.data(using: .utf8) {
        let snapshot = try JSONDecoder().decode(AuroraSnapshot.self, from: data)
        guard snapshot.version == 1 else { throw NSError(domain: "Aurora", code: 2) }
        defaults.set(data, forKey: AuroraShared.key)
      } else { defaults.removeObject(forKey: AuroraShared.key) }
      WidgetCenter.shared.reloadAllTimelines()
    }
    AsyncFunction("syncNap") { (start: Double?) async throws -> Bool in
      if #available(iOS 16.2, *) {
        let desired = start.map { String($0) }
        for activity in Activity<AuroraNapAttributes>.activities where activity.attributes.sessionID != desired {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let start = start else { return true }
        guard start.isFinite, start <= Date().timeIntervalSince1970 * 1000, Date().timeIntervalSince1970 * 1000 - start <= 86400000 else { return false }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        if Activity<AuroraNapAttributes>.activities.contains(where: { $0.attributes.sessionID == desired }) { return true }
        let state = AuroraNapAttributes.ContentState(startedAt: AuroraShared.date(start))
        _ = try Activity.request(attributes: AuroraNapAttributes(sessionID: String(start)), content: ActivityContent(state: state, staleDate: AuroraShared.date(start + 86400000)), pushType: nil)
        return true
      }
      return false
    }
  }
}
