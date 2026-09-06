import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct AuroraNapAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable { let startedAt: Date }
  let sessionID: String
}
