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
/// Aurora's own entries twice.
///
/// Metadata is never proof of ownership: any app can set a sync identifier
/// or custom key. A sample is Aurora's only when Health reports Aurora's
/// exact bundle as its source, or when its UUID is one Health returned for an
/// Aurora save and the ledger kept.
public enum HealthOrigin {
    public static let appBundleIdentifier = "com.nmapaye.aurora"
    public static let syncIdentifierPrefix = "com.nmapaye.aurora.dose."
    /// Custom metadata key carrying the Aurora record id.
    public static let recordIDMetadataKey = "AuroraRecordID"

    public enum Ownership: Equatable, Sendable {
        /// Written by another app or device.
        case thirdParty
        /// Aurora's, and the dose it came from is still recorded here.
        case ownWithLocalDose(doseID: String)
        /// Aurora's, but no recorded dose matches it, as after full erase and
        /// reconnecting. It is kept as a read-only Health record.
        case ownWithoutLocalDose
    }

    public static func syncIdentifier(forDoseID id: String) -> String {
        "\(syncIdentifierPrefix)\(id)"
    }

    public static func isOwnExport(_ provenance: HealthSampleProvenance, ledger: HealthSyncLedger) -> Bool {
        provenance.sourceBundleIdentifier == appBundleIdentifier
            || ledger.ownExports.contains { $0.sampleUUID == provenance.sampleUUID }
    }

    /// Classifies a sample. The sync identifier is used only to find the
    /// local dose of a sample already proven to be Aurora's.
    public static func ownership(of provenance: HealthSampleProvenance, ledger: HealthSyncLedger, doses: [Dose]) -> Ownership {
        guard isOwnExport(provenance, ledger: ledger) else { return .thirdParty }
        let local = doses.filter { !RecordID.isHealthCaffeine($0.id) && !RecordID.isSample($0.id) }
        if let export = ledger.ownExports.first(where: { $0.sampleUUID == provenance.sampleUUID }),
           local.contains(where: { $0.id == export.doseID }) {
            return .ownWithLocalDose(doseID: export.doseID)
        }
        if let sync = provenance.syncIdentifier,
           let dose = local.first(where: { syncIdentifier(forDoseID: $0.id) == sync }) {
            return .ownWithLocalDose(doseID: dose.id)
        }
        return .ownWithoutLocalDose
    }
}

public enum HealthCaffeineImport {
    public struct Result: Equatable, Sendable {
        public var upserted = 0
        public var removed = 0
        /// Aurora's own samples whose dose is still recorded here.
        public var skippedOwn = 0
        /// Aurora's own samples with no recorded dose, kept as read-only
        /// Health records so they aren't lost. Counted in `upserted` too.
        public var keptOwnWithoutLocalDose = 0
        public var rejected = 0

        public init() {}
    }

    /// A sample with an identity, a finite time and a positive finite amount.
    public static func isValid(_ sample: HealthCaffeineSample) -> Bool {
        !sample.provenance.sampleUUID.isEmpty
            && sample.timestamp.isFinite
            && sample.mg.isFinite && sample.mg > 0
    }

    public static func dose(from sample: HealthCaffeineSample) -> Dose {
        Dose(id: sample.recordID, timestamp: sample.timestamp, mg: sample.mg, health: sample.provenance)
    }
}
