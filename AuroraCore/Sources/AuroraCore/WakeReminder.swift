import Foundation

/// Caffeine reminders the person sets relative to waking, e.g. one hour and
/// five hours after waking. The times are theirs; Aurora never suggests them.
public struct WakeReminderSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Minutes after waking, one reminder each.
    public var offsetsMinutes: [Int]
    /// The fallback when no wake-up is recorded, in minutes after midnight.
    public var usualWakeMinutes: Int

    public static let defaults = WakeReminderSettings(enabled: false, offsetsMinutes: [60], usualWakeMinutes: 8 * 60)

    public init(enabled: Bool, offsetsMinutes: [Int], usualWakeMinutes: Int) {
        self.enabled = enabled
        self.offsetsMinutes = offsetsMinutes
        self.usualWakeMinutes = usualWakeMinutes
    }

    /// Offsets sorted, unique, within range and at most `maxOffsets`; the
    /// usual wake time within one day.
    public func normalized() -> WakeReminderSettings {
        let offsets = Array(Set(offsetsMinutes.filter { WakeReminders.offsetRange.contains($0) })).sorted().prefix(WakeReminders.maxOffsets)
        return WakeReminderSettings(
            enabled: enabled,
            offsetsMinutes: Array(offsets),
            usualWakeMinutes: min(max(usualWakeMinutes, 0), 24 * 60 - 1)
        )
    }
}

public enum WakeReminders {
    public static let identifierPrefix = "wake-reminder-"
    public static let offsetRange = 15...(12 * 60)
    public static let maxOffsets = 4
    /// A reminder whose time passed this recently, because the wake-up
    /// reached Aurora late, still fires right away instead of being dropped.
    public static let lateGraceMs: Millis = 30 * minuteMs
    /// Offsets offered as one-tap choices.
    public static let presetOffsets = [30, 60, 90, 120, 180, 240, 300, 360]

    public enum Basis: Equatable, Sendable {
        case recordedWake(Millis)
        case usualWake(Millis)
    }

    public struct Reminder: Equatable, Sendable, Identifiable {
        public var id: String
        public var fireAt: Millis
        public var offsetMinutes: Int
        public var basis: Basis
        public var title: String
        public var body: String
    }

    /// The final wake-up recorded today: the end of the latest sleep (not a
    /// nap, not Sample Data) that ended by now and no earlier than the later
    /// of 4:00 and three hours before the usual wake time, so a wake-up in
    /// the middle of the night doesn't count.
    public static func recordedWake(sleeps: [SleepSession], usualWakeMinutes: Int, now: Millis, clock: LocalClock) -> Millis? {
        let dayStart = clock.startOfDay(now)
        let usual = clock.setTime(dayStart, hour: usualWakeMinutes / 60, minute: usualWakeMinutes % 60)
        let earliest = max(clock.setTime(dayStart, hour: 4), usual - 3 * hourMs)
        return sleeps
            .filter { $0.type == .sleep && !RecordID.isSample($0.id) && $0.end <= now && $0.end >= earliest }
            .map(\.end)
            .max()
    }

    /// Reminders for the rest of today and for tomorrow. Today uses the
    /// recorded wake-up when there is one, otherwise the usual wake time;
    /// tomorrow always starts from the usual wake time and is replaced once
    /// a wake-up is recorded. Nothing at or after the person's cutoff, nothing
    /// already delivered, and nothing in the past except a recorded-wake
    /// reminder within `lateGraceMs`.
    public static func plan(
        settings: WakeReminderSettings,
        cutoffHour: Double,
        sleeps: [SleepSession],
        now: Millis,
        clock: LocalClock,
        text: DateText,
        delivered: Set<String> = []
    ) -> [Reminder] {
        let settings = settings.normalized()
        guard settings.enabled, !settings.offsetsMinutes.isEmpty else { return [] }
        let today = clock.startOfDay(now)
        var reminders: [Reminder] = []
        for dayStart in [today, clock.addingDays(1, to: today)] {
            let usual = clock.setTime(dayStart, hour: settings.usualWakeMinutes / 60, minute: settings.usualWakeMinutes % 60)
            let recorded = dayStart == today
                ? recordedWake(sleeps: sleeps, usualWakeMinutes: settings.usualWakeMinutes, now: now, clock: clock)
                : nil
            let basis: Basis = recorded.map { .recordedWake($0) } ?? .usualWake(usual)
            let wake = recorded ?? usual
            let cutoffWhole = Int(floor(cutoffHour))
            let cutoff = clock.setTime(dayStart, hour: cutoffWhole, minute: Int(jsRound((cutoffHour - Double(cutoffWhole)) * 60)))
            for offset in settings.offsetsMinutes {
                let id = "\(identifierPrefix)\(clock.dayKey(dayStart))-\(offset)"
                guard !delivered.contains(id) else { continue }
                var fireAt = wake + Millis(offset) * minuteMs
                guard fireAt < cutoff else { continue }
                if fireAt <= now {
                    guard recorded != nil, now - fireAt <= lateGraceMs else { continue }
                    fireAt = now + minuteMs
                }
                reminders.append(Reminder(
                    id: id,
                    fireAt: fireAt,
                    offsetMinutes: offset,
                    basis: basis,
                    title: "Your caffeine reminder",
                    body: body(offset: offset, basis: basis, text: text)
                ))
            }
        }
        return reminders
    }

    static func body(offset: Int, basis: Basis, text: DateText) -> String {
        switch basis {
        case .recordedWake(let wake): "\(offsetText(offset)) after waking · woke at \(text.clockTime(wake))"
        case .usualWake(let wake): "\(offsetText(offset)) after your usual \(text.clockTime(wake)) wake time"
        }
    }

    /// "45 min", "1 h", "1 h 30 min".
    public static func offsetText(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
