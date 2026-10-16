import Foundation

/// One logged caffeine entry. `source` is the drink label ("Drip",
/// "Espresso"), not where the record came from; that comes from the id.
/// Health-imported entries also keep the sample's provenance. It is absent
/// from every other entry, so their stored JSON keeps its original keys.
public struct Dose: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var timestamp: Millis
    public var mg: Double
    public var source: String?
    public var note: String?
    public var health: HealthSampleProvenance?

    public init(
        id: String,
        timestamp: Millis,
        mg: Double,
        source: String? = nil,
        note: String? = nil,
        health: HealthSampleProvenance? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mg = mg
        self.source = source
        self.note = note
        self.health = health
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
    /// Health sleep read with its sample identity keeps the provenance Health
    /// reported. Absent everywhere else, so stored sessions keep their keys.
    public var health: HealthSampleProvenance?

    public init(id: String, start: Millis, end: Millis, type: SleepType = .sleep, note: String? = nil, health: HealthSampleProvenance? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.type = type
        self.note = note
        self.health = health
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
    /// Some of Health's changes were read; the rest follow at the next
    /// refresh. Never shown as current or as "no sleep found".
    case partial
}

public struct Prefs: Codable, Equatable, Sendable {
    /// Caffeine half-life in hours.
    public var halfLife: Double
    /// Nightly sleep target in hours, nil until the person chooses one.
    /// Nothing is pre-selected and no reference is substituted while unset.
    public var targetSleep: Double?
    public var tz: String?
    /// The user's own stored reference. It is never presented as a limit,
    /// allowance or goal.
    public var dailyLimitMg: Double
    public var cutoffHour: Double
    public var notifyCutoff: Bool
    /// What Aurora calls the person in greetings. Optional, stays on device,
    /// and isn't written while unset.
    public var displayName: String?
    /// `CaffeinePreset` ids chosen as favorites. Optional and isn't written
    /// while unset.
    public var favoriteDrinkIDs: [String]?
    /// Caffeine reminders the person set relative to waking. Nil until set
    /// up, and in files from older builds.
    public var wakeReminders: WakeReminderSettings?
    /// Next-day follow-ups on yesterday's drinks. Nil (off) until turned on,
    /// and in files from older builds.
    public var repeatDrinks: RepeatDrinkSettings?

    public static let defaultHalfLife: Double = 5

    public static let defaults = Prefs(
        halfLife: defaultHalfLife,
        targetSleep: nil,
        tz: nil,
        dailyLimitMg: 400,
        cutoffHour: 16,
        notifyCutoff: false
    )

    public init(
        halfLife: Double,
        targetSleep: Double?,
        tz: String? = nil,
        dailyLimitMg: Double,
        cutoffHour: Double,
        notifyCutoff: Bool,
        displayName: String? = nil,
        favoriteDrinkIDs: [String]? = nil,
        wakeReminders: WakeReminderSettings? = nil,
        repeatDrinks: RepeatDrinkSettings? = nil
    ) {
        self.halfLife = halfLife
        self.targetSleep = targetSleep
        self.tz = tz
        self.dailyLimitMg = dailyLimitMg
        self.cutoffHour = cutoffHour
        self.notifyCutoff = notifyCutoff
        self.displayName = displayName
        self.favoriteDrinkIDs = favoriteDrinkIDs
        self.wakeReminders = wakeReminders
        self.repeatDrinks = repeatDrinks
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
    /// The next unanswered first-run setup question (`SetupStep` raw value),
    /// so a relaunch resumes there. Nil before setup starts and in files
    /// from older builds; not written while nil.
    public var setupStep: Int?
    /// What the person actually did at each setup question they were asked,
    /// keyed by `SetupStep` raw value: `SetupOutcome` raw values. Questions
    /// passed over by "Skip to the end" have no entry. Plain strings so a
    /// value from another build is ignored instead of failing the decode.
    /// Nil in older files; not written while nil.
    public var setupOutcomes: [String: String]?

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
        appWalkthroughStep: Int,
        setupStep: Int? = nil,
        setupOutcomes: [String: String]? = nil
    ) {
        self.completed = completed
        self.source = source
        self.permissionStatus = permissionStatus
        self.completedAt = completedAt
        self.appWalkthroughCompleted = appWalkthroughCompleted
        self.appWalkthroughStep = appWalkthroughStep
        self.setupStep = setupStep
        self.setupOutcomes = setupOutcomes
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
    public static let healthCaffeinePrefix = "healthkit:caffeine:"
    public static let energyCheckInPrefix = "checkin:"

    public static func isSample(_ id: String) -> Bool {
        id.hasPrefix(samplePrefix)
    }

    public static func isHealthSleep(_ id: String) -> Bool {
        id.hasPrefix(healthSleepPrefix)
    }

    /// `healthkit:sleep:sample:<sample uuid>`: Health sleep read with its
    /// sample identity. Two samples with the same interval stay two records.
    public static let healthSleepSamplePrefix = "healthkit:sleep:sample:"

    public static func healthSleepID(sampleUUID: String) -> String {
        "\(healthSleepSamplePrefix)\(sampleUUID.lowercased())"
    }

    public static func isHealthSleepSample(_ id: String) -> Bool {
        id.hasPrefix(healthSleepSamplePrefix)
    }

    /// Health sleep from before sample identity: `healthkit:sleep:<start>:<end>`.
    public static func isLegacyHealthSleep(_ id: String) -> Bool {
        isHealthSleep(id) && !isHealthSleepSample(id)
    }

    /// Health caffeine is read-only here; Health owns the record.
    public static func isHealthCaffeine(_ id: String) -> Bool {
        id.hasPrefix(healthCaffeinePrefix)
    }

    /// `healthkit:caffeine:<sample uuid>`. The Health sample UUID is the only
    /// identity: two samples with the same time and amount stay two entries.
    public static func healthCaffeineID(sampleUUID: String) -> String {
        "\(healthCaffeinePrefix)\(sampleUUID.lowercased())"
    }

    /// Energy check-in ids: `checkin:<ms>:<entropy>`.
    public static func newEnergyCheckInID(now: Millis, entropy: String = RecordID.entropy()) -> String {
        "\(energyCheckInPrefix)\(Int64(now)):\(entropy)"
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
