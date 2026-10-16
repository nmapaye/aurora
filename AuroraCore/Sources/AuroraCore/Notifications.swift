import Foundation

/// How many push notifications Aurora may start on its own.
///
/// Two kinds of notification exist:
/// - **Set by the person:** the daily cutoff reminder, wake reminders and a
///   saved cutoff-scenario reminder. The person chose each time, so they
///   never count toward Aurora's cap.
/// - **Started by Aurora:** the morning briefing and drink follow-ups. At
///   most `auroraInitiatedPerDay` of these reach the lock screen a day.
///   When more than one is on, `Kind` order decides: the briefing first,
///   then follow-ups, which then stay in the conversation only.
///
/// Proactive suggestions (sleep updates, upcoming commitments) are in-app
/// cards only and never push; `ProactivePolicy` caps them separately at two
/// a day.
public enum NotificationBudget {
    public static let auroraInitiatedPerDay = 1

    /// Priority order, highest first.
    public enum Kind: Int, CaseIterable, Comparable, Sendable {
        case morningBriefing
        case drinkFollowUps

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Whether the morning briefing notification is on: suggestions and the
    /// briefing switched on, at an hour outside quiet hours.
    public static func briefingNotifies(_ preferences: AssistantPreferences) -> Bool {
        preferences.proactive && preferences.morningBriefing
            && !ProactivePolicy.isQuiet(hour: preferences.briefingHour, preferences: preferences)
    }

    /// The kinds that may notify when `wanted` are switched on: the highest
    /// priorities, up to the daily cap.
    public static func allowed(_ wanted: Set<Kind>) -> Set<Kind> {
        Set(wanted.sorted().prefix(auroraInitiatedPerDay))
    }

    /// Whether drink follow-ups may notify, given the briefing setting.
    public static func followUpsMayNotify(_ preferences: AssistantPreferences) -> Bool {
        let wanted: Set<Kind> = briefingNotifies(preferences) ? [.morningBriefing, .drinkFollowUps] : [.drinkFollowUps]
        return allowed(wanted).contains(.drinkFollowUps)
    }
}

/// The person's own cutoff time on a given day.
public enum CutoffTime {
    /// The instant of `hour` (hours after midnight, fractions as minutes) on
    /// the local day starting at `dayStart`; nil when no time is set.
    public static func at(dayStart: Millis, hour: Double?, clock: LocalClock) -> Millis? {
        guard let hour, hour.isFinite else { return nil }
        let bounded = clamp(hour, 0, 24)
        let whole = Int(floor(bounded))
        return clock.setTime(dayStart, hour: whole, minute: Int(jsRound((bounded - Double(whole)) * 60)))
    }
}
