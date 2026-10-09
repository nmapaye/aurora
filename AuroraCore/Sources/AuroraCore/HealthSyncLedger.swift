import Foundation

public enum HealthDataKind: String, Codable, Sendable, CaseIterable {
    case sleepAnalysis
    case caffeine
}

/// An archived `HKQueryAnchor` for one data kind.
public struct HealthQueryAnchor: Codable, Equatable, Sendable {
    public var kind: HealthDataKind
    public var data: Data
    public var updatedAt: Millis

    public init(kind: HealthDataKind, data: Data, updatedAt: Millis) {
        self.kind = kind
        self.data = data
        self.updatedAt = updatedAt
    }
}

/// A caffeine entry Aurora has written, or will write, to Health.
public struct HealthOwnExport: Codable, Equatable, Sendable {
    public var doseID: String
    public var syncIdentifier: String
    public var syncVersion: Int
    /// Set once Health confirms the save.
    public var sampleUUID: String?
    public var exportedAt: Millis?
    /// The time and amount Health received, so a local correction that
    /// wasn't exported shows as not matching.
    public var timestamp: Millis?
    public var mg: Double?

    public init(
        doseID: String, syncIdentifier: String, syncVersion: Int, sampleUUID: String? = nil, exportedAt: Millis? = nil,
        timestamp: Millis? = nil, mg: Double? = nil
    ) {
        self.doseID = doseID
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.sampleUUID = sampleUUID
        self.exportedAt = exportedAt
        self.timestamp = timestamp
        self.mg = mg
    }

    /// Whether Health holds this dose as it is recorded now.
    public func matches(_ dose: Dose) -> Bool {
        timestamp == dose.timestamp && mg == dose.mg
    }
}

/// A Health write that hasn't completed. One per dose: a newer request for
/// the same dose replaces the older one.
public struct HealthPendingAction: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case saveCaffeine
        case deleteCaffeine
    }

    public var id: String
    public var kind: Kind
    public var doseID: String
    public var syncIdentifier: String
    public var syncVersion: Int
    public var createdAt: Millis
    public var attempts: Int
    /// Saved before Health is asked. If it's set on an action that never
    /// finished, the write may have reached Health, so a retry checks first.
    public var startedAt: Millis?

    public init(
        id: String, kind: Kind, doseID: String, syncIdentifier: String, syncVersion: Int, createdAt: Millis,
        attempts: Int = 0, startedAt: Millis? = nil
    ) {
        self.id = id
        self.kind = kind
        self.doseID = doseID
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.createdAt = createdAt
        self.attempts = attempts
        self.startedAt = startedAt
    }
}

public struct HealthSyncOutcome: Codable, Equatable, Sendable {
    /// Marks a cancelled action that Health had already been asked to do.
    public static let startedBeforeCancel = "started"

    public enum Result: String, Codable, Sendable {
        case succeeded
        case failed
        /// Dropped without asking Health, after export was turned off.
        case cancelled
    }

    public var actionID: String
    public var kind: HealthPendingAction.Kind
    public var doseID: String
    public var result: Result
    public var message: String?
    public var finishedAt: Millis

    public init(actionID: String, kind: HealthPendingAction.Kind, doseID: String, result: Result, message: String? = nil, finishedAt: Millis) {
        self.actionID = actionID
        self.kind = kind
        self.doseID = doseID
        self.result = result
        self.message = message
        self.finishedAt = finishedAt
    }
}

/// The last anchored caffeine read: counts only, no health values.
public struct HealthReadRecord: Codable, Equatable, Sendable {
    public var finishedAt: Millis
    public var added: Int
    public var removed: Int
    /// Set when the read failed. The anchor didn't move.
    public var failure: String?

    public init(finishedAt: Millis, added: Int = 0, removed: Int = 0, failure: String? = nil) {
        self.finishedAt = finishedAt
        self.added = added
        self.removed = removed
        self.failure = failure
    }
}

/// Health sync bookkeeping, stored with the records. Nothing here is a
/// health value; it is what Aurora needs to resume anchored reads and to
/// recognise and manage its own writes.
public struct HealthSyncLedger: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// Recent outcomes kept for display and diagnosis; older ones drop off.
    public static let outcomeLimit = 50

    public var version: Int = HealthSyncLedger.currentVersion
    public var anchors: [HealthQueryAnchor] = []
    public var ownExports: [HealthOwnExport] = []
    public var pendingActions: [HealthPendingAction] = []
    public var outcomes: [HealthSyncOutcome] = []
    public var lastCaffeineRead: HealthReadRecord?

    public static let empty = HealthSyncLedger()

    public init() {}

    /// A ledger written by a newer build is kept as stored, and Health sync
    /// pauses rather than guess at it.
    public var isSupported: Bool { version <= Self.currentVersion }

    public func pendingAction(forDoseID id: String) -> HealthPendingAction? {
        pendingActions.first { $0.doseID == id }
    }

    public func lastOutcome(forDoseID id: String) -> HealthSyncOutcome? {
        outcomes.last { $0.doseID == id }
    }

    /// Recorded before Health is called, so after a relaunch Aurora knows
    /// the write may have landed.
    public mutating func markStarted(actionID: String, at now: Millis) {
        guard let index = pendingActions.firstIndex(where: { $0.id == actionID }) else { return }
        pendingActions[index].startedAt = now
    }

    /// Drops every queued action and records each one as cancelled. Exports
    /// already in Health stay there.
    public mutating func cancelPending(now: Millis) {
        for action in pendingActions {
            // An action already sent to Health may still have landed.
            let message = action.startedAt == nil ? nil : HealthSyncOutcome.startedBeforeCancel
            appendOutcome(HealthSyncOutcome(actionID: action.id, kind: action.kind, doseID: action.doseID, result: .cancelled, message: message, finishedAt: now))
        }
        pendingActions = []
    }

    /// Forgets a save that never started, so nothing reached Health.
    @discardableResult
    public mutating func dropUnstartedSave(forDoseID id: String) -> Bool {
        guard let action = pendingAction(forDoseID: id), action.kind == .saveCaffeine, action.startedAt == nil else { return false }
        pendingActions.removeAll { $0.id == action.id }
        return true
    }

    private mutating func appendOutcome(_ outcome: HealthSyncOutcome) {
        outcomes.append(outcome)
        if outcomes.count > Self.outcomeLimit { outcomes.removeFirst(outcomes.count - Self.outcomeLimit) }
    }

    public func anchor(for kind: HealthDataKind) -> HealthQueryAnchor? {
        anchors.first { $0.kind == kind }
    }

    public mutating func setAnchor(_ data: Data, for kind: HealthDataKind, at now: Millis) {
        anchors.removeAll { $0.kind == kind }
        anchors.append(HealthQueryAnchor(kind: kind, data: data, updatedAt: now))
    }

    public func ownExport(forDoseID id: String) -> HealthOwnExport? {
        ownExports.first { $0.doseID == id }
    }

    /// Queues a save or delete for a dose Aurora recorded. The sync version
    /// moves past any earlier export so Health keeps the newest copy.
    @discardableResult
    public mutating func enqueue(_ kind: HealthPendingAction.Kind, doseID: String, now: Millis, id: String) -> HealthPendingAction {
        let previous = max(ownExport(forDoseID: doseID)?.syncVersion ?? 0, pendingActions.first { $0.doseID == doseID }?.syncVersion ?? 0)
        let action = HealthPendingAction(
            id: id, kind: kind, doseID: doseID,
            syncIdentifier: HealthOrigin.syncIdentifier(forDoseID: doseID),
            syncVersion: previous + 1, createdAt: now
        )
        pendingActions.removeAll { $0.doseID == doseID }
        pendingActions.append(action)
        return action
    }

    /// Records how a pending action ended. Success settles the own-export
    /// identity; failure keeps the action queued with one more attempt.
    public mutating func finish(
        actionID: String, result: HealthSyncOutcome.Result, sampleUUID: String? = nil, exported dose: Dose? = nil,
        message: String? = nil, now: Millis
    ) {
        guard let index = pendingActions.firstIndex(where: { $0.id == actionID }) else { return }
        let action = pendingActions[index]
        appendOutcome(HealthSyncOutcome(actionID: action.id, kind: action.kind, doseID: action.doseID, result: result, message: message, finishedAt: now))
        guard result == .succeeded else {
            pendingActions[index].attempts += 1
            return
        }
        pendingActions.remove(at: index)
        ownExports.removeAll { $0.doseID == action.doseID }
        if action.kind == .saveCaffeine {
            ownExports.append(HealthOwnExport(
                doseID: action.doseID, syncIdentifier: action.syncIdentifier, syncVersion: action.syncVersion,
                sampleUUID: sampleUUID?.lowercased(), exportedAt: now, timestamp: dose?.timestamp, mg: dose?.mg
            ))
        }
    }
}

extension HealthSyncLedger {
    private enum CodingKeys: String, CodingKey {
        case version, anchors, ownExports, pendingActions, outcomes, lastCaffeineRead
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? HealthSyncLedger.currentVersion
        anchors = try container.decodeIfPresent([HealthQueryAnchor].self, forKey: .anchors) ?? []
        ownExports = try container.decodeIfPresent([HealthOwnExport].self, forKey: .ownExports) ?? []
        pendingActions = try container.decodeIfPresent([HealthPendingAction].self, forKey: .pendingActions) ?? []
        outcomes = try container.decodeIfPresent([HealthSyncOutcome].self, forKey: .outcomes) ?? []
        lastCaffeineRead = try container.decodeIfPresent(HealthReadRecord.self, forKey: .lastCaffeineRead)
    }
}
