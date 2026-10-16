import Foundation

/// What a Health provider can do. Each operation is separate so a provider
/// can offer reading without writing, and callers check before asking.
public struct HealthCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let authorization = HealthCapabilities(rawValue: 1 << 0)
    public static let readSleep = HealthCapabilities(rawValue: 1 << 1)
    public static let readCaffeineChanges = HealthCapabilities(rawValue: 1 << 2)
    public static let writeOwnCaffeine = HealthCapabilities(rawValue: 1 << 3)
    public static let deleteOwnCaffeine = HealthCapabilities(rawValue: 1 << 4)
    public static let observeChanges = HealthCapabilities(rawValue: 1 << 5)
    /// Anchored sleep reads with sample identity and deletions.
    public static let readSleepChanges = HealthCapabilities(rawValue: 1 << 6)
    /// Health may wake Aurora for observed changes (iOS: the
    /// `com.apple.developer.healthkit.background-delivery` entitlement).
    public static let backgroundDelivery = HealthCapabilities(rawValue: 1 << 7)
    /// Window reads of Sleep Analysis "In bed" samples, under the same read
    /// permission as sleep.
    public static let readInBed = HealthCapabilities(rawValue: 1 << 8)
}

public enum HealthProviderError: Error, Equatable, Sendable {
    case unavailable
    /// The provider doesn't offer this operation.
    case unsupported(String)
    /// The stored read position couldn't be decoded. Reading from nothing
    /// would lose deletions, so the read fails and nothing changes.
    case invalidAnchor(HealthDataKind)
}

/// A caffeine entry Aurora recorded, as it would be written to Health.
public struct HealthCaffeineWrite: Equatable, Sendable {
    public var doseID: String
    public var timestamp: Millis
    public var mg: Double
    public var syncIdentifier: String
    public var syncVersion: Int

    public init(doseID: String, timestamp: Millis, mg: Double, syncIdentifier: String, syncVersion: Int) {
        self.doseID = doseID
        self.timestamp = timestamp
        self.mg = mg
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
    }
}

public struct HealthObservation: Hashable, Sendable {
    public var id: String
    public var kinds: Set<HealthDataKind>

    public init(id: String, kinds: Set<HealthDataKind>) {
        self.id = id
        self.kinds = kinds
    }
}

/// Aurora's only route to Health. Defaults throw `unsupported`, so a
/// provider implements just what its `capabilities` declare.
public protocol HealthDataProvider: Sendable {
    var capabilities: HealthCapabilities { get }
    var isAvailable: Bool { get }

    /// Shows the Health sheet. Completion says nothing about what was
    /// allowed: Health never reveals read decisions.
    func requestAuthorization(read: Set<HealthDataKind>, write: Set<HealthDataKind>) async throws
    /// Asleep samples that end inside the window, oldest first.
    func sleepSamples(from start: Millis, to end: Millis) async throws -> [HealthSleepSample]
    func caffeineChanges(after anchor: Data?) async throws -> HealthCaffeineChanges
    /// Asleep samples added, with identity, and samples deleted since `anchor`.
    func sleepChanges(after anchor: Data?) async throws -> HealthSleepChanges
    /// "In bed" samples overlapping the window, with identity, oldest first.
    /// Never asleep time: callers keep them apart from sleep.
    func inBedSamples(from start: Millis, to end: Millis) async throws -> [HealthSleepSample]
    /// Turns Health's wake-ups for changes to `kinds` on or off. Health
    /// decides when and how often it actually delivers.
    func setBackgroundDelivery(_ kinds: Set<HealthDataKind>, enabled: Bool) async throws
    /// Saves one of Aurora's own entries; returns the Health sample UUID.
    func saveOwnCaffeine(_ write: HealthCaffeineWrite) async throws -> String
    /// Deletes only samples Aurora wrote with this sync identifier.
    func deleteOwnCaffeine(syncIdentifier: String) async throws
    /// Aurora's own sample with this sync identifier, if Health has one.
    /// Used before retrying an interrupted save so it isn't written twice.
    /// Part of `writeOwnCaffeine`.
    func ownCaffeineSample(syncIdentifier: String) async throws -> HealthSampleProvenance?
    /// `onChange` runs once per Health notification; the provider tells
    /// Health the notification was handled only after it returns.
    func startObserving(_ kinds: Set<HealthDataKind>, onChange: @escaping @Sendable (HealthDataKind) async -> Void) async throws -> HealthObservation
    func stopObserving(_ observation: HealthObservation)
}

extension HealthDataProvider {
    public func requestAuthorization(read: Set<HealthDataKind>, write: Set<HealthDataKind>) async throws {
        throw HealthProviderError.unsupported("authorization")
    }

    public func sleepSamples(from start: Millis, to end: Millis) async throws -> [HealthSleepSample] {
        throw HealthProviderError.unsupported("readSleep")
    }

    public func caffeineChanges(after anchor: Data?) async throws -> HealthCaffeineChanges {
        throw HealthProviderError.unsupported("readCaffeineChanges")
    }

    public func sleepChanges(after anchor: Data?) async throws -> HealthSleepChanges {
        throw HealthProviderError.unsupported("readSleepChanges")
    }

    public func inBedSamples(from start: Millis, to end: Millis) async throws -> [HealthSleepSample] {
        throw HealthProviderError.unsupported("readInBed")
    }

    public func setBackgroundDelivery(_ kinds: Set<HealthDataKind>, enabled: Bool) async throws {
        throw HealthProviderError.unsupported("backgroundDelivery")
    }

    public func saveOwnCaffeine(_ write: HealthCaffeineWrite) async throws -> String {
        throw HealthProviderError.unsupported("writeOwnCaffeine")
    }

    public func deleteOwnCaffeine(syncIdentifier: String) async throws {
        throw HealthProviderError.unsupported("deleteOwnCaffeine")
    }

    public func ownCaffeineSample(syncIdentifier: String) async throws -> HealthSampleProvenance? {
        throw HealthProviderError.unsupported("writeOwnCaffeine")
    }

    public func startObserving(_ kinds: Set<HealthDataKind>, onChange: @escaping @Sendable (HealthDataKind) async -> Void) async throws -> HealthObservation {
        throw HealthProviderError.unsupported("observeChanges")
    }

    public func stopObserving(_ observation: HealthObservation) {}
}
