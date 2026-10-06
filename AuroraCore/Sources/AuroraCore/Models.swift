import Foundation

/// One logged caffeine entry. `source` is the drink label ("Drip",
/// "Espresso"), not where the record came from; that comes from the id.
public struct Dose: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var timestamp: Millis
    public var mg: Double
    public var source: String?
    public var note: String?

    public init(id: String, timestamp: Millis, mg: Double, source: String? = nil, note: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.mg = mg
        self.source = source
        self.note = note
    }
}

public enum SleepType: String, Codable, Sendable {
    case sleep
    case nap
}

public struct SleepSession: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var start: Millis
    public var end: Millis
    public var type: SleepType
    public var note: String?

    public init(id: String, start: Millis, end: Millis, type: SleepType = .sleep, note: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.type = type
        self.note = note
    }
}

/// The start and end of any sleep interval, for the algorithms that ignore
/// ids and types.
public struct Interval: Equatable, Sendable {
    public var start: Millis
    public var end: Millis

    public init(start: Millis, end: Millis) {
        self.start = start
        self.end = end
    }
}

public enum AppearanceMode: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark
}

public enum OnboardingSource: String, Codable, Sendable {
    case healthkit
    case manual
}

/// `granted` means the permission request completed. HealthKit never says
/// whether read access was actually allowed.
public enum HealthPermissionStatus: String, Codable, Sendable {
    case idle
    case granted
    case denied
    case unsupported
}

public enum HealthImportStatus: String, Codable, Sendable {
    case idle
    case importing
    case succeeded
    case failed
}

public struct Prefs: Codable, Equatable, Sendable {
    /// Caffeine half-life in hours.
    public var halfLife: Double
    /// Nightly sleep target in hours.
    public var targetSleep: Double
    public var tz: String?
    /// The user's own stored reference. It is never presented as a limit,
    /// allowance or goal.
    public var dailyLimitMg: Double
    public var cutoffHour: Double
    public var notifyCutoff: Bool

    public static let defaultHalfLife: Double = 5
    public static let defaultTargetSleep: Double = 8

    public static let defaults = Prefs(
        halfLife: defaultHalfLife,
        targetSleep: defaultTargetSleep,
        tz: nil,
        dailyLimitMg: 400,
        cutoffHour: 16,
        notifyCutoff: false
    )

    public init(
        halfLife: Double,
        targetSleep: Double,
        tz: String? = nil,
        dailyLimitMg: Double,
        cutoffHour: Double,
        notifyCutoff: Bool
    ) {
        self.halfLife = halfLife
        self.targetSleep = targetSleep
        self.tz = tz
        self.dailyLimitMg = dailyLimitMg
        self.cutoffHour = cutoffHour
        self.notifyCutoff = notifyCutoff
    }
}

public struct Onboarding: Codable, Equatable, Sendable {
    public var completed: Bool
    public var source: OnboardingSource
    public var permissionStatus: HealthPermissionStatus
    public var completedAt: Millis?
    public var appWalkthroughCompleted: Bool
    /// 0 through 9.
    public var appWalkthroughStep: Int

    public static let defaults = Onboarding(
        completed: false,
        source: .healthkit,
        permissionStatus: .idle,
        completedAt: nil,
        appWalkthroughCompleted: false,
        appWalkthroughStep: 0
    )

    public init(
        completed: Bool,
        source: OnboardingSource,
        permissionStatus: HealthPermissionStatus,
        completedAt: Millis? = nil,
        appWalkthroughCompleted: Bool,
        appWalkthroughStep: Int
    ) {
        self.completed = completed
        self.source = source
        self.permissionStatus = permissionStatus
        self.completedAt = completedAt
        self.appWalkthroughCompleted = appWalkthroughCompleted
        self.appWalkthroughStep = appWalkthroughStep
    }
}

public struct HealthSync: Codable, Equatable, Sendable {
    public var lastSyncedAt: Millis?
    public var lastMessage: String?
    public var importedCount: Int
    public var importStatus: HealthImportStatus

    public static let defaults = HealthSync(lastSyncedAt: nil, lastMessage: nil, importedCount: 0, importStatus: .idle)

    public init(lastSyncedAt: Millis? = nil, lastMessage: String? = nil, importedCount: Int, importStatus: HealthImportStatus) {
        self.lastSyncedAt = lastSyncedAt
        self.lastMessage = lastMessage
        self.importedCount = importedCount
        self.importStatus = importStatus
    }
}

/// Ids carry the record's origin; it is never stored as a separate field.
public enum RecordID {
    public static let samplePrefix = "demo:"
    public static let healthSleepPrefix = "healthkit:sleep:"
    public static let manualSleepPrefix = "manual:sleep:"

    public static func isSample(_ id: String) -> Bool {
        id.hasPrefix(samplePrefix)
    }

    public static func isHealthSleep(_ id: String) -> Bool {
        id.hasPrefix(healthSleepPrefix)
    }

    public static func isManualSleep(_ id: String) -> Bool {
        id.hasPrefix(manualSleepPrefix)
    }

    /// Base-36 digits, as `Number.prototype.toString(36)` writes them.
    public static func base36(_ value: Int64) -> String {
        String(value, radix: 36)
    }

    /// Random lowercase base-36 characters, standing in for
    /// `Math.random().toString(36).slice(2)`.
    public static func entropy(length: Int = 11) -> String {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }

    /// Dose ids: `<base36 ms>-<entropy>`.
    public static func newDoseID(now: Millis, entropy: String = RecordID.entropy()) -> String {
        "\(base36(Int64(now)))-\(entropy)"
    }

    /// Manual sleep ids: `manual:sleep:<ms>:<entropy>`.
    public static func newManualSleepID(now: Millis, entropy: String = RecordID.entropy()) -> String {
        "\(manualSleepPrefix)\(Int64(now)):\(entropy)"
    }

    /// Reaction Test ids: `vig-<base36 ms>-<6 chars>`.
    public static func newVigilanceID(now: Millis, entropy: String = RecordID.entropy(length: 6)) -> String {
        "vig-\(base36(Int64(now)))-\(entropy)"
    }
}
