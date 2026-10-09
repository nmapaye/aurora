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
}

public enum HealthProviderError: Error, Equatable, Sendable {
    case unavailable
    /// The provider doesn't offer this operation.
    case unsupported(String)
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
    /// Saves one of Aurora's own entries; returns the Health sample UUID.
    func saveOwnCaffeine(_ write: HealthCaffeineWrite) async throws -> String
    /// Deletes only samples Aurora wrote with this sync identifier.
    func deleteOwnCaffeine(syncIdentifier: String) async throws
    func startObserving(_ kinds: Set<HealthDataKind>, onChange: @escaping @Sendable (HealthDataKind) -> Void) async throws -> HealthObservation
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

    public func saveOwnCaffeine(_ write: HealthCaffeineWrite) async throws -> String {
        throw HealthProviderError.unsupported("writeOwnCaffeine")
    }

    public func deleteOwnCaffeine(syncIdentifier: String) async throws {
        throw HealthProviderError.unsupported("deleteOwnCaffeine")
    }

    public func startObserving(_ kinds: Set<HealthDataKind>, onChange: @escaping @Sendable (HealthDataKind) -> Void) async throws -> HealthObservation {
        throw HealthProviderError.unsupported("observeChanges")
    }

    public func stopObserving(_ observation: HealthObservation) {}
}
