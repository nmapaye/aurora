import AuroraCore
import Foundation
import HealthKit

/// Archives `HKQueryAnchor` with secure coding. A missing anchor means the
/// first read; stored data that won't decode is an error, never treated as
/// a first read, because starting over would lose deletions.
enum HealthAnchorCodec {
    static func decode(_ data: Data?, kind: HealthDataKind) throws -> HKQueryAnchor? {
        guard let data else { return nil }
        let anchor: HKQueryAnchor?
        do {
            anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        } catch {
            throw HealthProviderError.invalidAnchor(kind)
        }
        guard let anchor else { throw HealthProviderError.invalidAnchor(kind) }
        return anchor
    }

    static func encode(_ anchor: HKQueryAnchor) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }
}
