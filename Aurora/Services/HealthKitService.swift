import AuroraCore
import Foundation
import HealthKit

/// Read-only access to Sleep Analysis. Aurora never writes to Health.
/// HealthKit doesn't reveal whether read access was allowed, so a completed
/// request is all the app ever knows.
final class HealthKitService: @unchecked Sendable {
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

    /// Aurora asks to write nothing and to read only Sleep Analysis.
    static let shareTypes: Set<HKSampleType> = []
    static let readTypes: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis)]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows the Health sheet. Returns once the request completes, whatever
    /// the person chose.
    func requestReadAccess() async throws {
        guard isAvailable else { throw Failure.unavailable }
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
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
