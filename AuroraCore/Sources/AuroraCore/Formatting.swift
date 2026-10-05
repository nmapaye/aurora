import Foundation

/// Locale-dependent text for times and dates. Screens use `.current`; tests
/// pass fixed closures so results don't depend on the machine's locale.
public struct DateText: Sendable {
    /// "9:41 AM"
    public var clockTime: @Sendable (Millis) -> String
    /// "Sep 24"
    public var shortDate: @Sendable (Millis) -> String
    /// "Sun, Sep 21"
    public var weekdayDate: @Sendable (Millis) -> String
    /// "Sun, Sep 27, 2026, 9:41 AM"
    public var fullDateTime: @Sendable (Millis) -> String

    public init(
        clockTime: @escaping @Sendable (Millis) -> String,
        shortDate: @escaping @Sendable (Millis) -> String,
        weekdayDate: @escaping @Sendable (Millis) -> String,
        fullDateTime: @escaping @Sendable (Millis) -> String
    ) {
        self.clockTime = clockTime
        self.shortDate = shortDate
        self.weekdayDate = weekdayDate
        self.fullDateTime = fullDateTime
    }

    public static func localized(locale: Locale = .current, timeZone: TimeZone = .current) -> DateText {
        func formatter(_ template: String) -> @Sendable (Millis) -> String {
            { ms in
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.timeZone = timeZone
                formatter.setLocalizedDateFormatFromTemplate(template)
                return formatter.string(from: Date(timeIntervalSince1970: ms / 1000))
            }
        }
        return DateText(
            clockTime: formatter("jmm"),
            shortDate: formatter("MMMd"),
            weekdayDate: formatter("EEEMMMd"),
            fullDateTime: formatter("EEEMMMdyyyyjmm")
        )
    }

    public static var current: DateText { localized() }

    /// "4:00 PM" for a whole hour from 0 to 23.
    public func clockHour(_ hour: Double, clock: LocalClock) -> String {
        let whole = Int(clamp(jsRound(hour), 0, 23))
        let reference = clock.setTime(Millis(1_767_225_600_000), hour: whole)
        return clockTime(reference)
    }
}

/// "7h 5m" from milliseconds, rounded to the minute.
public func formatHoursMinutes(durationMs: Millis) -> String {
    let totalMinutes = jsRoundInt(durationMs / minuteMs)
    let hours = Int(floor(Double(totalMinutes) / 60))
    let minutes = totalMinutes - hours * 60
    return "\(hours)h \(minutes)m"
}

/// "7h 5m" from hours, rounded to the minute.
public func formatSleepHours(_ hours: Double) -> String {
    formatHoursMinutes(durationMs: hours * hourMs)
}

/// "40m", "2h", "7h 15m": compact gaps for context lines.
public func formatGap(durationMs: Millis) -> String {
    let totalMinutes = jsRoundInt(abs(durationMs) / minuteMs)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours == 0 { return "\(minutes)m" }
    return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
}

func plural(_ count: Int, _ one: String, _ many: String? = nil) -> String {
    "\(count) \(count == 1 ? one : (many ?? one + "s"))"
}

/// Whole-number text the way JavaScript prints a number: "95", "12.5".
public func numberText(_ value: Double) -> String {
    if value.rounded() == value, abs(value) < 1e15 {
        return String(Int64(value))
    }
    return String(value)
}
