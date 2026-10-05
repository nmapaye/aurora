import Foundation

/// Milliseconds since the Unix epoch. Records are stored this way, as JSON
/// numbers, so the values read from the React Native build round-trip exactly.
public typealias Millis = Double

public let minuteMs: Millis = 60_000
public let hourMs: Millis = 3_600_000
public let dayMs: Millis = 86_400_000

/// JavaScript's `Math.round`: halves round toward positive infinity, so
/// -2.5 becomes -2. Swift's default rounding would give -3.
@inlinable
public func jsRound(_ value: Double) -> Double {
    (value + 0.5).rounded(.down)
}

@inlinable
public func jsRoundInt(_ value: Double) -> Int {
    Int(jsRound(value))
}

@inlinable
func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(upper, max(lower, value))
}

/// Local calendar arithmetic with the same results as the JavaScript `Date`
/// setters the React Native build used (`setHours`, `setDate`). Every
/// day-based rule takes one of these, so tests can pin the time zone.
public struct LocalClock: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public init(timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public static var current: LocalClock {
        LocalClock(timeZone: .current)
    }

    public var timeZone: TimeZone { calendar.timeZone }

    func date(_ ms: Millis) -> Date {
        Date(timeIntervalSince1970: ms / 1000)
    }

    func millis(_ date: Date) -> Millis {
        (date.timeIntervalSince1970 * 1000).rounded()
    }

    /// Local midnight at the start of the day containing `ms`.
    public func startOfDay(_ ms: Millis) -> Millis {
        millis(calendar.startOfDay(for: date(ms)))
    }

    /// The same local day as `ms` at `hour:minute:second.millisecond`
    /// (`Date.setHours`). An hour of 24 is midnight at the end of that day.
    public func setTime(
        _ ms: Millis,
        hour: Int,
        minute: Int = 0,
        second: Int = 0,
        millisecond: Int = 0
    ) -> Millis {
        let start = calendar.startOfDay(for: date(ms))
        var components = calendar.dateComponents([.year, .month, .day], from: start)
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = millisecond * 1_000_000
        guard let result = calendar.date(from: components) else {
            return millis(start) + Millis(hour) * hourMs
        }
        return millis(result)
    }

    /// Moves `ms` by whole calendar days, keeping the local wall-clock time
    /// (`Date.setDate(getDate() + days)`).
    public func addingDays(_ days: Int, to ms: Millis) -> Millis {
        guard let result = calendar.date(byAdding: .day, value: days, to: date(ms)) else {
            return ms + Millis(days) * dayMs
        }
        return millis(result)
    }

    public func hour(_ ms: Millis) -> Int {
        calendar.component(.hour, from: date(ms))
    }

    /// Year, month and day as a key: two instants share a key only when they
    /// fall on the same local calendar day.
    public func dayKey(_ ms: Millis) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date(ms))
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// "2026-09-27" in local time.
    public func isoDay(_ ms: Millis) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date(ms))
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Local midnights of the `days` calendar days ending with the day of `now`,
    /// oldest first.
    public func dayStarts(endingAt now: Millis, days: Int) -> [Millis] {
        let end = startOfDay(now)
        return (0..<max(0, days)).map { index in
            addingDays(-(days - 1 - index), to: end)
        }
    }
}

/// ISO 8601 with milliseconds in UTC, matching `Date.prototype.toISOString`.
public func isoTimestamp(_ ms: Millis) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return formatter.string(from: Date(timeIntervalSince1970: ms / 1000))
}
