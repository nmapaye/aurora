import AuroraCore
import Foundation
import HealthKit

/// Read-only access to Sleep Analysis. Aurora never writes to Health.
/// HealthKit doesn't reveal whether read access was allowed, so a completed
/// request is all the app ever knows.
///
/// This is the compatibility adapter for `HealthDataProvider`: it offers
/// authorization and sleep reads only. Caffeine reads, own writes, deletes
/// and observers keep the protocol's `unsupported` defaults until the Health
/// package implements them.
final class HealthKitService: HealthDataProvider, @unchecked Sendable {
    enum Failure: LocalizedError {
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable: "Apple Health isn’t available on this device."
            }
        }
    }

    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var capabilities: HealthCapabilities { [.authorization, .readSleep] }

    /// Shows the Health sheet for Sleep Analysis read access. Returns once the
    /// request completes, whatever the person chose. Anything beyond reading
    /// sleep is refused before Health is asked.
    func requestAuthorization(read: Set<HealthDataKind>, write: Set<HealthDataKind>) async throws {
        guard read == [.sleepAnalysis], write.isEmpty else {
            throw HealthProviderError.unsupported("authorization beyond Sleep Analysis read")
        }
        guard isAvailable else { throw Failure.unavailable }
        try await store.requestAuthorization(toShare: [], read: [sleepType])
    }

    /// Asleep samples (unspecified, core, deep, REM) that end inside the
    /// window, oldest first.
    func sleepSamples(from start: Millis, to end: Millis) async throws -> [HealthSleepSample] {
        guard isAvailable else { throw Failure.unavailable }
        let predicate = HKQuery.predicateForSamples(
            withStart: Date(timeIntervalSince1970: start / 1000),
            end: Date(timeIntervalSince1970: end / 1000),
            options: []
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)
        return samples
            .filter { HealthImport.asleepValues.contains($0.value) }
            .map {
                HealthSleepSample(
                    start: ($0.startDate.timeIntervalSince1970 * 1000).rounded(),
                    end: ($0.endDate.timeIntervalSince1970 * 1000).rounded()
                )
            }
    }
}
