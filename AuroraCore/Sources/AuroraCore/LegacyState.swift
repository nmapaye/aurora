import Foundation

/// Any JSON value, for reading the React Native build's loosely typed blob.
public enum JSONValue: Equatable, Sendable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(parsing data: Data) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var object: [String: JSONValue]? {
        if case .object(let object) = self { return object }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let array) = self { return array }
        return nil
    }

    var string: String? {
        if case .string(let string) = self { return string }
        return nil
    }

    var bool: Bool? {
        if case .bool(let bool) = self { return bool }
        return nil
    }

    /// Finite numbers only, like `Number.isFinite`.
    var finite: Double? {
        if case .number(let number) = self, number.isFinite { return number }
        return nil
    }

    /// The largest instant JavaScript's `Date` can hold, in milliseconds
    /// either side of the epoch. The React Native build couldn't use a time
    /// outside it (it became an Invalid Date), and calendar arithmetic that
    /// far out isn't meaningful, so such a time marks the record malformed.
    static let maxInstant: Double = 8.64e15

    /// A finite number inside JavaScript's `Date` range.
    var instant: Millis? {
        guard let number = finite, abs(number) <= Self.maxInstant else { return nil }
        return number
    }
}

/// Reads the React Native build's persisted store (`aurora/state` in MMKV):
/// `{"state": {...}, "version": N}`. Applies that build's migrations for
/// versions below 6, then the same validation it ran on every load, so the
/// Swift app starts with exactly the records the old app would have shown.
public enum LegacyState {
    public static let currentVersion = 6

    public enum Failure: Error, Equatable {
        case unreadable
    }

    public static func decode(_ raw: String, now: Millis) throws -> AppState {
        guard let data = raw.data(using: .utf8), let root = try? JSONValue(parsing: data) else {
            throw Failure.unreadable
        }
        let state = root["state"]?.object ?? [:]
        let version = root["version"]?.finite.map(Int.init) ?? 0
        return normalize(migrate(state, version: version), now: now)
    }

    static func migrate(_ input: [String: JSONValue], version: Int) -> [String: JSONValue] {
        var state = input
        if version < 2 {
            state["vigilanceSessions"] = .array([])
        }
        if version < 4 {
            var onboarding = state["onboarding"]?.object ?? [:]
            onboarding["summaryWalkthroughCompleted"] = .bool(onboarding["completed"]?.bool == true)
            state["onboarding"] = .object(onboarding)
        }
        if version < 5 {
            var onboarding = state["onboarding"]?.object ?? [:]
            onboarding["appWalkthroughCompleted"] = .bool(onboarding["summaryWalkthroughCompleted"]?.bool == true)
            onboarding["appWalkthroughStep"] = .number(0)
            state["onboarding"] = .object(onboarding)
        }
        if version < 6 {
            var healthSync = state["healthSync"]?.object ?? [:]
            let permission = state["onboarding"]?["permissionStatus"]?.string
                .flatMap(HealthPermissionStatus.init(rawValue:)) ?? .idle
            healthSync["importStatus"] = .string(
                importStatus(nil, permission: permission, lastMessage: healthSync["lastMessage"]?.string).rawValue
            )
            state["healthSync"] = .object(healthSync)
        }
        return state
    }

    static func importStatus(_ value: JSONValue?, permission: HealthPermissionStatus, lastMessage: String?) -> HealthImportStatus {
        guard permission == .granted else { return .idle }
        if let value {
            switch value.string {
            case "idle": return .idle
            case "succeeded": return .succeeded
            case "failed": return .failed
            default: return .idle
            }
        }
        let message = lastMessage?.lowercased() ?? ""
        if message.hasPrefix("health import failed.") || message.hasPrefix("health refresh failed.") {
            return .failed
        }
        if message.hasPrefix("imported ") || message.hasPrefix("health connected") {
            return .succeeded
        }
        return .idle
    }

    static func id(_ value: JSONValue?) -> String? {
        guard let string = value?.string, !string.isEmpty else { return nil }
        return string
    }

    static func dose(_ value: JSONValue) -> Dose? {
        guard let object = value.object,
              let id = id(object["id"]),
              let timestamp = object["timestamp"]?.instant,
              let mg = object["mg"]?.finite, mg >= 0 else { return nil }
        return Dose(id: id, timestamp: timestamp, mg: mg, source: object["source"]?.string, note: object["note"]?.string)
    }

    static func sleep(_ value: JSONValue) -> SleepSession? {
        guard let object = value.object,
              let id = id(object["id"]),
              let start = object["start"]?.instant,
              let end = object["end"]?.instant, end > start,
              let type = object["type"]?.string.flatMap(SleepType.init(rawValue:)) else { return nil }
        return SleepSession(id: id, start: start, end: end, type: type, note: object["note"]?.string)
    }

    static func vigilance(_ value: JSONValue) -> VigilanceSession? {
        guard let object = value.object,
              let id = id(object["id"]),
              let startedAt = object["startedAt"]?.instant,
              let completedAt = object["completedAt"]?.instant,
              let score = object["score"]?.finite,
              let ratingText = object["rating"]?.string else { return nil }
        // "Fatigued" read as a diagnosis; older results get the softer label.
        // Scores are 0-100 and counts are never negative; a stored value outside
        // that (only a damaged or hand-edited store has one) is pulled back in
        // rather than carried through as a giant number.
        let boundedScore = clamp(jsRoundInt(score), 0, 100)
        let rating = VigilanceRating(rawValue: ratingText == "Fatigued" ? "Sluggish" : ratingText)
            ?? Vigilance.rating(for: boundedScore)
        func int(_ key: String) -> Int { max(0, object[key]?.finite.map(jsRoundInt) ?? 0) }
        return VigilanceSession(
            id: id,
            startedAt: startedAt,
            completedAt: completedAt,
            durationMs: object["durationMs"]?.finite ?? (completedAt - startedAt),
            trialCount: int("trialCount"),
            validReactionCount: int("validReactionCount"),
            falseStartCount: int("falseStartCount"),
            lapseCount: int("lapseCount"),
            medianReactionMs: object["medianReactionMs"]?.finite,
            meanReactionMs: object["meanReactionMs"]?.finite,
            fastestReactionMs: object["fastestReactionMs"]?.finite,
            reactionStdDevMs: object["reactionStdDevMs"]?.finite,
            score: boundedScore,
            rating: rating
        )
    }

    static func normalize(_ state: [String: JSONValue], now: Millis) -> AppState {
        var result = AppState()
        result.doses = state["doses"]?.array?.compactMap(dose) ?? []
        result.sleeps = AppState.withinHealthRetention(
            HealthSleepIdentity.normalize(state["sleeps"]?.array?.compactMap(sleep) ?? []),
            now: now
        )
        result.vigilanceSessions = state["vigilanceSessions"]?.array?.compactMap(vigilance) ?? []

        let prefs = state["prefs"]?.object ?? [:]
        var normalizedPrefs = Prefs.defaults
        if let value = prefs["halfLife"]?.finite { normalizedPrefs.halfLife = value }
        if let value = prefs["targetSleep"]?.finite { normalizedPrefs.targetSleep = value }
        if let value = prefs["dailyLimitMg"]?.finite { normalizedPrefs.dailyLimitMg = value }
        if let value = prefs["cutoffHour"]?.finite { normalizedPrefs.cutoffHour = value }
        if let value = prefs["notifyCutoff"]?.bool { normalizedPrefs.notifyCutoff = value }
        if let value = prefs["tz"]?.string { normalizedPrefs.tz = value }
        result.prefs = normalizedPrefs

        let onboarding = state["onboarding"]?.object ?? [:]
        var normalizedOnboarding = Onboarding.defaults
        if let value = onboarding["completed"]?.bool { normalizedOnboarding.completed = value }
        if let value = onboarding["source"]?.string.flatMap(OnboardingSource.init(rawValue:)) { normalizedOnboarding.source = value }
        if let value = onboarding["permissionStatus"]?.string.flatMap(HealthPermissionStatus.init(rawValue:)) {
            normalizedOnboarding.permissionStatus = value
        }
        if let value = onboarding["completedAt"]?.instant { normalizedOnboarding.completedAt = value }
        if let value = onboarding["appWalkthroughCompleted"]?.bool { normalizedOnboarding.appWalkthroughCompleted = value }
        normalizedOnboarding.appWalkthroughStep = onboarding["appWalkthroughStep"]?.finite
            .map { AppState.clampWalkthroughStep(Int(floor(clamp($0, -1, 100)))) } ?? 0
        result.onboarding = normalizedOnboarding

        let healthSync = state["healthSync"]?.object ?? [:]
        var normalizedSync = HealthSync.defaults
        if let value = healthSync["lastSyncedAt"]?.instant { normalizedSync.lastSyncedAt = value }
        if let value = healthSync["lastMessage"]?.string { normalizedSync.lastMessage = value }
        if let value = healthSync["importedCount"]?.finite { normalizedSync.importedCount = max(0, jsRoundInt(value)) }
        if healthSync["importStatus"]?.string == "importing" {
            normalizedSync.lastMessage = "Health import was interrupted. Try again."
        }
        normalizedSync.importStatus = importStatus(
            healthSync["importStatus"],
            permission: normalizedOnboarding.permissionStatus,
            lastMessage: healthSync["lastMessage"]?.string
        )
        result.healthSync = normalizedSync

        result.demoMode = state["demoMode"]?.bool ?? false
        result.appearanceMode = state["appearanceMode"]?.string.flatMap(AppearanceMode.init(rawValue:)) ?? .system
        return result
    }
}
