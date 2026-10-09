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

    public init(doseID: String, syncIdentifier: String, syncVersion: Int, sampleUUID: String? = nil, exportedAt: Millis? = nil) {
        self.doseID = doseID
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.sampleUUID = sampleUUID
        self.exportedAt = exportedAt
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

    public init(id: String, kind: Kind, doseID: String, syncIdentifier: String, syncVersion: Int, createdAt: Millis, attempts: Int = 0) {
        self.id = id
        self.kind = kind
        self.doseID = doseID
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.createdAt = createdAt
        self.attempts = attempts
    }
}

public struct HealthSyncOutcome: Codable, Equatable, Sendable {
    public enum Result: String, Codable, Sendable {
        case succeeded
        case failed
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

    public static let empty = HealthSyncLedger()

    public init() {}

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
    public mutating func finish(actionID: String, result: HealthSyncOutcome.Result, sampleUUID: String? = nil, message: String? = nil, now: Millis) {
        guard let index = pendingActions.firstIndex(where: { $0.id == actionID }) else { return }
        let action = pendingActions[index]
        outcomes.append(HealthSyncOutcome(actionID: action.id, kind: action.kind, doseID: action.doseID, result: result, message: message, finishedAt: now))
        if outcomes.count > Self.outcomeLimit { outcomes.removeFirst(outcomes.count - Self.outcomeLimit) }
        guard result == .succeeded else {
            pendingActions[index].attempts += 1
            return
        }
        pendingActions.remove(at: index)
        ownExports.removeAll { $0.doseID == action.doseID }
        if action.kind == .saveCaffeine {
            ownExports.append(HealthOwnExport(
                doseID: action.doseID, syncIdentifier: action.syncIdentifier, syncVersion: action.syncVersion,
                sampleUUID: sampleUUID?.lowercased(), exportedAt: now
            ))
        }
    }
}

extension HealthSyncLedger {
    private enum CodingKeys: String, CodingKey {
        case version, anchors, ownExports, pendingActions, outcomes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? HealthSyncLedger.currentVersion
        anchors = try container.decodeIfPresent([HealthQueryAnchor].self, forKey: .anchors) ?? []
        ownExports = try container.decodeIfPresent([HealthOwnExport].self, forKey: .ownExports) ?? []
        pendingActions = try container.decodeIfPresent([HealthPendingAction].self, forKey: .pendingActions) ?? []
        outcomes = try container.decodeIfPresent([HealthSyncOutcome].self, forKey: .outcomes) ?? []
    }
}
