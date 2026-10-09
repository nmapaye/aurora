import AuroraCore
import Foundation
import HealthKit

/// Aurora's HealthKit adapter. It reads Sleep Analysis and dietary caffeine,
/// and writes or deletes only caffeine samples Aurora saved itself. Each
/// permission is requested on its own, when the person turns that choice on.
/// HealthKit doesn't reveal whether read access was allowed, so a completed
/// request is all the app ever knows about reading.
final class HealthKitService: HealthDataProvider, @unchecked Sendable {
    enum Failure: LocalizedError {
        case unavailable
        case notAllowed
        case unreadableSample

        var errorDescription: String? {
            switch self {
            case .unavailable: "Apple Health isn’t available on this device."
            case .notAllowed: "Apple Health didn’t accept this. Check Aurora in the Health app’s Sharing settings."
            case .unreadableSample: "Apple Health returned a sample Aurora couldn’t read."
            }
        }
    }

    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let caffeineType = HKQuantityType(.dietaryCaffeine)
    private let milligrams = HKUnit.gramUnit(with: .milli)
    private let lock = NSLock()
    private var queries: [String: HKObserverQuery] = [:]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    /// Background delivery needs the HealthKit Background Delivery
    /// entitlement, declared in `Aurora.entitlements`. Without it Health
    /// refuses `enableBackgroundDelivery`, and the choice stays off.
    var capabilities: HealthCapabilities {
        [.authorization, .readSleep, .readSleepChanges, .readCaffeineChanges, .writeOwnCaffeine, .deleteOwnCaffeine,
         .observeChanges, .backgroundDelivery]
    }

    private func objectType(_ kind: HealthDataKind) -> HKSampleType {
        switch kind {
        case .sleepAnalysis: sleepType
        case .caffeine: caffeineType
        }
    }

    /// Shows the Health sheet for exactly the kinds asked for. Aurora only
    /// ever writes caffeine. Returns once the request completes, whatever
    /// the person chose.
    func requestAuthorization(read: Set<HealthDataKind>, write: Set<HealthDataKind>) async throws {
        guard !(read.isEmpty && write.isEmpty), write.isSubset(of: [.caffeine]) else {
            throw HealthProviderError.unsupported("authorization")
        }
        guard isAvailable else { throw Failure.unavailable }
        try await store.requestAuthorization(
            toShare: Set(write.map { objectType($0) }),
            read: Set(read.map { objectType($0) as HKObjectType })
        )
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

    /// Asleep samples added since `anchor`, each with its UUID and source,
    /// and the UUIDs of samples deleted since then. In-bed and awake samples
    /// aren't sleep and are left out; their deletions match nothing here.
    func sleepChanges(after anchor: Data?) async throws -> HealthSleepChanges {
        guard isAvailable else { throw Failure.unavailable }
        let previous = anchor.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [.categorySample(type: sleepType)], anchor: previous)
        let result = try await descriptor.result(for: store)
        let next = try NSKeyedArchiver.archivedData(withRootObject: result.newAnchor, requiringSecureCoding: true)
        return HealthSleepChanges(
            added: result.addedSamples
                .filter { HealthImport.asleepValues.contains($0.value) }
                .map {
                    HealthSleepSample(
                        start: ($0.startDate.timeIntervalSince1970 * 1000).rounded(),
                        end: ($0.endDate.timeIntervalSince1970 * 1000).rounded(),
                        provenance: provenance($0)
                    )
                },
            deletedSampleUUIDs: result.deletedObjects.map { $0.uuid.uuidString.lowercased() },
            anchor: next
        )
    }

    /// Health wakes Aurora at most hourly for these kinds while enabled, and
    /// keeps the setting across launches until it's turned off.
    func setBackgroundDelivery(_ kinds: Set<HealthDataKind>, enabled: Bool) async throws {
        guard isAvailable else { throw Failure.unavailable }
        for kind in kinds {
            let type = objectType(kind)
            if enabled {
                try await store.enableBackgroundDelivery(for: type, frequency: .hourly)
            } else {
                try await store.disableBackgroundDelivery(for: type)
            }
        }
    }

    // MARK: Caffeine

    /// Additions and deletions since `anchor`, from every source. The anchor
    /// is archived `HKQueryAnchor` data; one that won't unarchive starts
    /// over, which is safe because records match by sample UUID.
    func caffeineChanges(after anchor: Data?) async throws -> HealthCaffeineChanges {
        guard isAvailable else { throw Failure.unavailable }
        let previous = anchor.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: caffeineType)],
            anchor: previous
        )
        let result = try await descriptor.result(for: store)
        let next = try NSKeyedArchiver.archivedData(withRootObject: result.newAnchor, requiringSecureCoding: true)
        return HealthCaffeineChanges(
            added: result.addedSamples.map(sample),
            deletedSampleUUIDs: result.deletedObjects.map { $0.uuid.uuidString.lowercased() },
            anchor: next
        )
    }

    private func provenance(_ sample: HKSample) -> HealthSampleProvenance {
        HealthSampleProvenance(
            sampleUUID: sample.uuid.uuidString,
            sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
            sourceName: sample.sourceRevision.source.name,
            syncIdentifier: sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
            syncVersion: (sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue
        )
    }

    private func sample(_ sample: HKQuantitySample) -> HealthCaffeineSample {
        HealthCaffeineSample(
            provenance: provenance(sample),
            timestamp: (sample.startDate.timeIntervalSince1970 * 1000).rounded(),
            mg: sample.quantity.doubleValue(for: milligrams)
        )
    }

    /// Saves one of Aurora's entries. The sync identifier and version let
    /// Health keep a single, newest copy of each entry.
    func saveOwnCaffeine(_ write: HealthCaffeineWrite) async throws -> String {
        guard isAvailable else { throw Failure.unavailable }
        guard store.authorizationStatus(for: caffeineType) == .sharingAuthorized else { throw Failure.notAllowed }
        let date = Date(timeIntervalSince1970: write.timestamp / 1000)
        let sample = HKQuantitySample(
            type: caffeineType,
            quantity: HKQuantity(unit: milligrams, doubleValue: write.mg),
            start: date, end: date,
            metadata: [
                HKMetadataKeySyncIdentifier: write.syncIdentifier,
                HKMetadataKeySyncVersion: NSNumber(value: write.syncVersion),
                HealthOrigin.recordIDMetadataKey: write.doseID,
            ]
        )
        try await store.save(sample)
        return sample.uuid.uuidString.lowercased()
    }

    /// Aurora's own samples with this sync identifier. The source predicate
    /// keeps every other app's and device's samples out of reach.
    private func ownPredicate(syncIdentifier: String) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [syncIdentifier]),
        ])
    }

    func deleteOwnCaffeine(syncIdentifier: String) async throws {
        guard isAvailable else { throw Failure.unavailable }
        guard store.authorizationStatus(for: caffeineType) == .sharingAuthorized else { throw Failure.notAllowed }
        let predicate = ownPredicate(syncIdentifier: syncIdentifier)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.deleteObjects(of: caffeineType, predicate: predicate) { _, _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func ownCaffeineSample(syncIdentifier: String) async throws -> HealthSampleProvenance? {
        guard isAvailable else { throw Failure.unavailable }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: caffeineType, predicate: ownPredicate(syncIdentifier: syncIdentifier))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        return try await descriptor.result(for: store).first.map(provenance)
    }

    // MARK: Observers

    /// One observer query per kind. Health's completion handler always runs:
    /// after Aurora handles the change, or straight away on an error.
    func startObserving(_ kinds: Set<HealthDataKind>, onChange: @escaping @Sendable (HealthDataKind) async -> Void) async throws -> HealthObservation {
        guard isAvailable else { throw Failure.unavailable }
        let observation = HealthObservation(id: UUID().uuidString, kinds: kinds)
        for kind in kinds {
            let query = HKObserverQuery(sampleType: objectType(kind), predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task {
                    await onChange(kind)
                    completion()
                }
            }
            lock.withLock { queries["\(observation.id):\(kind.rawValue)"] = query }
            store.execute(query)
        }
        return observation
    }

    func stopObserving(_ observation: HealthObservation) {
        let stopped = lock.withLock {
            let keys = queries.keys.filter { $0.hasPrefix("\(observation.id):") }
            return keys.compactMap { queries.removeValue(forKey: $0) }
        }
        for query in stopped { store.stop(query) }
    }
}
