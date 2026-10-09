import Foundation

/// One Health choice the person can turn on by itself. A permission choice
/// asks Health for that permission alone; reading never implies writing.
/// `backgroundUpdates` asks for no permission: it lets Health wake Aurora
/// for the kinds it already reads.
public enum HealthChoice: String, Codable, CaseIterable, Sendable {
    case readSleep
    case readCaffeine
    case writeCaffeine
    case backgroundUpdates

    public var readKinds: Set<HealthDataKind> {
        switch self {
        case .readSleep: [.sleepAnalysis]
        case .readCaffeine: [.caffeine]
        case .writeCaffeine, .backgroundUpdates: []
        }
    }

    public var writeKinds: Set<HealthDataKind> { self == .writeCaffeine ? [.caffeine] : [] }

    /// What the provider must offer for this choice to work.
    public var requiredCapabilities: HealthCapabilities {
        switch self {
        case .readSleep: [.authorization, .readSleep]
        case .readCaffeine: [.authorization, .readCaffeineChanges]
        case .writeCaffeine: [.authorization, .writeOwnCaffeine, .deleteOwnCaffeine]
        case .backgroundUpdates: [.observeChanges, .backgroundDelivery]
        }
    }

    public var title: String {
        switch self {
        case .readSleep: "Read sleep"
        case .readCaffeine: "Read caffeine"
        case .writeCaffeine: "Add my caffeine to Health"
        case .backgroundUpdates: "Update in the background"
        }
    }

    public var detail: String {
        switch self {
        case .readSleep:
            "Imports Sleep Analysis. Imported sleep is read-only in Aurora."
        case .readCaffeine:
            "Imports caffeine that other apps and devices saved to Apple Health. Those entries are read-only in Aurora; change them in the Health app."
        case .writeCaffeine:
            "Adds caffeine you save in Aurora to Apple Health, and updates or removes only those entries. Entries from other sources are never changed. Erasing Aurora leaves its copies in Apple Health."
        case .backgroundUpdates:
            "Lets Apple Health wake Aurora when sleep or caffeine you chose to read changes, so imports stay current. When it’s off, Aurora reads Health when you open it and during occasional iOS background refreshes."
        }
    }

    /// Health tells apps whether writing was allowed, but never whether
    /// reading was, so a read choice only ever says it was requested.
    public var requestedNote: String {
        switch self {
        case .readSleep, .readCaffeine:
            "Requested. Health doesn’t tell apps what you allowed, so finding nothing can mean no records or no read access."
        case .writeCaffeine:
            "Requested. If Health doesn’t accept an entry, it stays saved here and is listed as not exported."
        case .backgroundUpdates:
            "On. Apple Health decides when to wake Aurora, at most about once an hour, and may delay or skip updates."
        }
    }
}

public struct HealthChoices: Codable, Equatable, Sendable {
    public var readSleep: Bool
    public var readCaffeine: Bool
    public var writeCaffeine: Bool
    public var backgroundUpdates: Bool

    public static let off = HealthChoices()

    public init(readSleep: Bool = false, readCaffeine: Bool = false, writeCaffeine: Bool = false, backgroundUpdates: Bool = false) {
        self.readSleep = readSleep
        self.readCaffeine = readCaffeine
        self.writeCaffeine = writeCaffeine
        self.backgroundUpdates = backgroundUpdates
    }

    public subscript(choice: HealthChoice) -> Bool {
        get {
            switch choice {
            case .readSleep: readSleep
            case .readCaffeine: readCaffeine
            case .writeCaffeine: writeCaffeine
            case .backgroundUpdates: backgroundUpdates
            }
        }
        set {
            switch choice {
            case .readSleep: readSleep = newValue
            case .readCaffeine: readCaffeine = newValue
            case .writeCaffeine: writeCaffeine = newValue
            case .backgroundUpdates: backgroundUpdates = newValue
            }
        }
    }

    /// Kinds Health may wake Aurora for: read kinds, only while opted in.
    public var backgroundKinds: Set<HealthDataKind> { backgroundUpdates ? observedKinds : [] }

    /// Kinds Aurora watches for changes: only those it reads.
    public var observedKinds: Set<HealthDataKind> {
        var kinds: Set<HealthDataKind> = []
        if readSleep { kinds.insert(.sleepAnalysis) }
        if readCaffeine { kinds.insert(.caffeine) }
        return kinds
    }
}

extension HealthChoices {
    private enum CodingKeys: String, CodingKey { case readSleep, readCaffeine, writeCaffeine, backgroundUpdates }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readSleep = try container.decodeIfPresent(Bool.self, forKey: .readSleep) ?? false
        readCaffeine = try container.decodeIfPresent(Bool.self, forKey: .readCaffeine) ?? false
        writeCaffeine = try container.decodeIfPresent(Bool.self, forKey: .writeCaffeine) ?? false
        backgroundUpdates = try container.decodeIfPresent(Bool.self, forKey: .backgroundUpdates) ?? false
    }
}

extension HealthSyncEngine.ChoiceResult {
    /// What to show beside the choice, or nil when nothing needs saying.
    public var message: String? {
        switch self {
        case .requested, .turnedOff, .discarded: nil
        case .unavailable: "Apple Health isn’t available on this device."
        case .unsupported: "This Health option isn’t available in this build."
        case .sampleData: "Turn off Sample Data to use Apple Health."
        case .paused: "Health sync is paused because these records came from a newer version of Aurora."
        case .failed(let message): message
        case .notSaved: "Couldn’t save this choice. Nothing else changed."
        }
    }
}

extension HealthSyncLedger {
    /// Queued and failed Health actions, for the Retry row. Nil when the
    /// outbox is empty.
    public var outboxSummary: String? {
        let failed = pendingActions.filter { $0.attempts > 0 }.count
        let waiting = pendingActions.count - failed
        guard failed + waiting > 0 else { return nil }
        var parts: [String] = []
        if failed > 0 { parts.append("\(failed) \(failed == 1 ? "change" : "changes") not accepted by Apple Health yet") }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        return parts.joined(separator: " · ") + ". Saved on this device either way."
    }

    /// The last caffeine read, in counts. Finding nothing is reported as
    /// nothing found, never as missing access.
    public var caffeineReadSummary: String? {
        guard let read = lastCaffeineRead else { return nil }
        if let failure = read.failure { return "Last caffeine read failed. \(failure)" }
        if read.added == 0 && read.removed == 0 { return "Last caffeine read found no changes." }
        return "Last caffeine read: \(read.added) added, \(read.removed) removed."
    }
}

/// Where one of Aurora's own entries stands in Health. Reported beside the
/// local outcome and never merged into it: saving here never depends on
/// Health, and nothing says "in Health" until Health confirmed it.
public enum HealthExportStatus: Equatable, Sendable {
    /// Nothing from this entry is in Health, and nothing is queued.
    case notExported
    /// Queued and not yet confirmed.
    case pending(HealthPendingAction.Kind)
    /// The last attempt failed. Still queued; Retry tries again.
    case failed(HealthPendingAction.Kind, String?)
    /// Health confirmed this entry as recorded now.
    case exported
    /// Health has an earlier version, and export is off so it wasn't updated.
    case outdated
    /// Removed here, while Aurora's earlier copy stays in Health.
    case keptInHealth
    /// Health confirmed Aurora's copy was removed.
    case removed
    /// Export was turned off before this entry's action ran.
    case cancelled
    /// Export was turned off while Health was already handling this entry,
    /// so whether the change landed is unknown.
    case uncertain

    public static func of(doseID: String, state: AppState) -> HealthExportStatus {
        let ledger = state.healthLedger
        if let action = ledger.pendingAction(forDoseID: doseID) {
            guard action.attempts > 0 else { return .pending(action.kind) }
            let message = ledger.outcomes.last { $0.actionID == action.id && $0.result == .failed }?.message
            return .failed(action.kind, message)
        }
        let dose = state.doses.first { $0.id == doseID }
        if let export = ledger.ownExport(forDoseID: doseID) {
            guard let dose else { return .keptInHealth }
            return export.matches(dose) ? .exported : .outdated
        }
        switch ledger.lastOutcome(forDoseID: doseID) {
        case let outcome? where outcome.kind == .deleteCaffeine && outcome.result == .succeeded: return .removed
        case let outcome? where outcome.result == .cancelled:
            return outcome.message == HealthSyncOutcome.startedBeforeCancel ? .uncertain : .cancelled
        default: return .notExported
        }
    }

    /// Short value for a receipt's Apple Health row, or nil when there is
    /// nothing to report.
    public var value: String? {
        switch self {
        case .notExported: nil
        case .pending(.saveCaffeine): "Export pending"
        case .pending(.deleteCaffeine): "Removal pending"
        case .failed(.saveCaffeine, _): "Not exported"
        case .failed(.deleteCaffeine, _): "Not removed"
        case .exported: "Added"
        case .outdated: "Earlier version"
        case .keptInHealth: "Earlier copy kept"
        case .removed: "Removed"
        case .cancelled: "Export off"
        case .uncertain: "Unconfirmed"
        }
    }

    public var detail: String {
        switch self {
        case .notExported: ""
        case .pending(.saveCaffeine): "Saved on this device. Waiting for Apple Health to confirm."
        case .pending(.deleteCaffeine): "Removed on this device. Waiting for Apple Health to remove Aurora’s copy."
        case .failed(.saveCaffeine, let message):
            "Saved on this device, not in Apple Health yet. Retry from Apple Health settings." + (message.map { " \($0)" } ?? "")
        case .failed(.deleteCaffeine, let message):
            "Removed on this device. Aurora’s copy is still in Apple Health. Retry from Apple Health settings." + (message.map { " \($0)" } ?? "")
        case .exported: "Apple Health confirmed Aurora’s copy of this entry."
        case .outdated: "Apple Health keeps the earlier version. Export is off, so it wasn’t updated."
        case .keptInHealth: "Aurora’s earlier copy stays in Apple Health. You can delete it in the Health app."
        case .removed: "Apple Health removed Aurora’s copy. Other sources were not changed."
        case .cancelled: "Export was turned off before this reached Apple Health. Saved on this device."
        case .uncertain: "Export was turned off while Apple Health was handling this entry, so Aurora can’t confirm the result. Check the Health app. Saved on this device."
        }
    }

    public var needsAttention: Bool {
        if case .failed = self { return true }
        return false
    }
}
