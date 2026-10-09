import Foundation

/// Where a Health sample came from, kept exactly as Health reported it.
public struct HealthSampleProvenance: Codable, Equatable, Hashable, Sendable {
    /// `HKObject.uuid`, lowercased.
    public var sampleUUID: String
    /// `HKSource.bundleIdentifier` of the app or device that wrote it.
    public var sourceBundleIdentifier: String
    public var sourceName: String?
    /// `HKMetadataKeySyncIdentifier` and `HKMetadataKeySyncVersion`, if set.
    public var syncIdentifier: String?
    public var syncVersion: Int?

    public init(
        sampleUUID: String,
        sourceBundleIdentifier: String,
        sourceName: String? = nil,
        syncIdentifier: String? = nil,
        syncVersion: Int? = nil
    ) {
        self.sampleUUID = sampleUUID.lowercased()
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceName = sourceName
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
    }
}

/// One dietary caffeine sample read from Health.
public struct HealthCaffeineSample: Equatable, Sendable {
    public var provenance: HealthSampleProvenance
    public var timestamp: Millis
    public var mg: Double

    public init(provenance: HealthSampleProvenance, timestamp: Millis, mg: Double) {
        self.provenance = provenance
        self.timestamp = timestamp
        self.mg = mg
    }

    public var recordID: String { RecordID.healthCaffeineID(sampleUUID: provenance.sampleUUID) }
}

/// An anchored read of caffeine: samples added or changed, and the UUIDs of
/// samples deleted, since the previous anchor.
public struct HealthCaffeineChanges: Equatable, Sendable {
    public var added: [HealthCaffeineSample]
    public var deletedSampleUUIDs: [String]
    /// The archived `HKQueryAnchor` to resume from.
    public var anchor: Data

    public init(added: [HealthCaffeineSample], deletedSampleUUIDs: [String], anchor: Data) {
        self.added = added
        self.deletedSampleUUIDs = deletedSampleUUIDs
        self.anchor = anchor
    }
}

/// How Aurora marks samples it writes, so reading them back never imports
/// Aurora's own entries as Health records.
public enum HealthOrigin {
    public static let appBundleIdentifier = "com.nmapaye.aurora"
    public static let syncIdentifierPrefix = "com.nmapaye.aurora.dose."
    /// Custom metadata key carrying the Aurora record id.
    public static let recordIDMetadataKey = "AuroraRecordID"

    public static func syncIdentifier(forDoseID id: String) -> String {
        "\(syncIdentifierPrefix)\(id)"
    }

    public static func isOwnExport(_ provenance: HealthSampleProvenance) -> Bool {
        provenance.sourceBundleIdentifier == appBundleIdentifier
            || provenance.sourceBundleIdentifier.hasPrefix(appBundleIdentifier + ".")
            || provenance.syncIdentifier?.hasPrefix(syncIdentifierPrefix) == true
    }
}

public enum HealthCaffeineImport {
    public struct Result: Equatable, Sendable {
        public var upserted = 0
        public var removed = 0
        public var skippedOwn = 0
        public var rejected = 0

        public init() {}
    }

    /// A sample Aurora can keep: not one of its own exports, with a finite
    /// time and a positive finite amount.
    public static func isEligible(_ sample: HealthCaffeineSample) -> Bool {
        !HealthOrigin.isOwnExport(sample.provenance)
            && !sample.provenance.sampleUUID.isEmpty
            && sample.timestamp.isFinite
            && sample.mg.isFinite && sample.mg > 0
    }

    public static func dose(from sample: HealthCaffeineSample) -> Dose {
        Dose(id: sample.recordID, timestamp: sample.timestamp, mg: sample.mg, health: sample.provenance)
    }
}
