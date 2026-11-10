import AuroraCore
import Foundation
import HealthKit
import Testing
@testable import Aurora

/// Secure-archive handling of HealthKit read positions. No Health store is
/// touched: anchors are built with `HKQueryAnchor(fromValue:)`.
@Suite struct HealthAnchorCodecTests {
    @Test func noAnchorIsAFirstRead() throws {
        #expect(try HealthAnchorCodec.decode(nil, kind: .caffeine) == nil)
    }

    @Test func aValidArchiveRoundTrips() throws {
        let anchor = HKQueryAnchor(fromValue: 42)
        let data = try HealthAnchorCodec.encode(anchor)
        let decoded = try #require(try HealthAnchorCodec.decode(data, kind: .sleepAnalysis))
        #expect(decoded == anchor)
    }

    @Test func corruptOrForeignArchivesFailExplicitly() throws {
        let valid = try HealthAnchorCodec.encode(HKQueryAnchor(fromValue: 7))
        let truncated = valid.prefix(valid.count / 2)
        let foreign = try NSKeyedArchiver.archivedData(withRootObject: "not an anchor" as NSString, requiringSecureCoding: true)
        for data in [Data(), Data("garbage".utf8), Data(truncated), foreign] {
            #expect(throws: HealthProviderError.invalidAnchor(.caffeine)) {
                try HealthAnchorCodec.decode(data, kind: .caffeine)
            }
        }
    }

    @Test func pagesAreBoundedAndAFullPageMayHaveMore() {
        #expect(HealthKitService.pageSize == 500)
        #expect(HealthKitService.isFullPage(added: 499, deleted: 1))
        #expect(!HealthKitService.isFullPage(added: 300, deleted: 10))
    }

    /// The anchored sleep read's HealthKit predicate comes from the tested
    /// Core filter: a start-date overlap and the asleep stages, nothing else.
    @Test func anchoredSleepPredicateIsTheCoreFilter() throws {
        #expect(Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)) == HealthImport.asleepValues)
        let now: Millis = 1_800_000_000_000
        let filter = HealthSleepReadFilter.anchored(now: now)
        let compound = try #require(HealthKitService.predicate(for: filter) as? NSCompoundPredicate)
        #expect(compound.compoundPredicateType == .and && compound.subpredicates.count == 2)
        let unbounded = try #require(HealthKitService.predicate(for: HealthSleepReadFilter(windowStart: nil)) as? NSCompoundPredicate)
        #expect(unbounded.subpredicates.count == 1)
        #expect(HealthKitService.pageSize == HealthImport.anchoredPageSize)
    }
}
