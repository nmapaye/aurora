import Foundation

/// Milliseconds since the Unix epoch. Records are stored this way, as JSON
/// numbers, so the values read from the React Native build round-trip exactly.
public typealias Millis = Double

/// The range a JavaScript `Date` can hold: 8.64e15 ms either side of the
/// epoch. A record time outside it, or not finite, has no calendar date;
/// the original app couldn't use one either.
public let maxRecordTime: Millis = 8.64e15

public func isValidRecordTime(_ ms: Millis) -> Bool {
    ms.isFinite && abs(ms) <= maxRecordTime
}

public let minuteMs: Millis = 60_000
public let hourMs: Millis = 3_600_000
public let dayMs: Millis = 86_400_000

/// JavaScript's `Math.round`: halves round toward positive infinity, so
/// -2.5 becomes -2. Swift's default rounding would give -3.
@inlinable
public func jsRound(_ value: Double) -> Double {
    (value + 0.5).rounded(.down)
}

/// `jsRound` as an `Int`. Stored records can hold any finite number, and
/// `Int(_:)` traps outside its range, so this saturates instead.
@inlinable
public func jsRoundInt(_ value: Double) -> Int {
    saturatingInt(jsRound(value))
}

/// `Int(value)` without the trap: NaN is 0, and values beyond `Int`'s range
/// become `Int.min` or `Int.max`. `Double(Int.max)` is 2^63, one past the
/// largest `Int`, so anything at or above it saturates.
@inlinable
public func saturatingInt(_ value: Double) -> Int {
    if value.isNaN { return 0 }
    if value >= Double(Int.max) { return .max }
    if value <= Double(Int.min) { return .min }
    return Int(value)
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

    /// The local calendar day containing `ms`: its midnight, and the next
    /// day's midnight (23 or 25 hours later across a DST change).
    public func dayBounds(_ ms: Millis) -> (start: Millis, end: Millis) {
        let start = startOfDay(ms)
        return (start, addingDays(1, to: start))
    }

    public func hour(_ ms: Millis) -> Int {
        calendar.component(.hour, from: date(ms))
    }

    /// The local calendar date of `ms`, with an astronomical year: Foundation
    /// counts Gregorian years within an era, so 6 Oct 2026 BC and AD share
    /// year 2026. Here 1 BC is year 0 and 2 BC is -1, as ISO 8601 numbers them.
    /// Before 15 Oct 1582 Foundation's Gregorian calendar gives Julian dates,
    /// where JavaScript extends the Gregorian one, so such old dates are
    /// distinct and ordered but can differ from the original's by days.
    /// A time outside `isValidRecordTime` gives (0, 0, 0) without asking the
    /// calendar, which can't place it.
    public func calendarDay(_ ms: Millis) -> (year: Int, month: Int, day: Int) {
        guard isValidRecordTime(ms) else { return (0, 0, 0) }
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date(ms))
        return (astronomicalYear(era: parts.era, year: parts.year), parts.month ?? 0, parts.day ?? 0)
    }

    /// Year, month and day as a key: two instants share a key only when they
    /// fall on the same local calendar day, BC dates included.
    public func dayKey(_ ms: Millis) -> String {
        let day = calendarDay(ms)
        return "\(day.year)-\(day.month)-\(day.day)"
    }

    /// "2026-09-27" in local time. Years before 1 AD use ISO 8601's expanded
    /// form, as `toISOString` does: 1 BC is "0000", 2026 BC is "-002025".
    /// An invalid time gives "", a blank cell in exports.
    public func isoDay(_ ms: Millis) -> String {
        guard isValidRecordTime(ms) else { return "" }
        let day = calendarDay(ms)
        return "\(isoYear(day.year))-\(twoDigits(day.month))-\(twoDigits(day.day))"
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

/// ISO 8601 with milliseconds in UTC, matching `Date.prototype.toISOString`,
/// including its expanded years ("-002025-10-06T12:00:00.000Z") outside
/// 0000-9999. The time is first truncated to whole milliseconds, as a
/// JavaScript `Date` stores it. Dates before 15 Oct 1582 come out in
/// Foundation's Julian reckoning (see `LocalClock.calendarDay`).
/// A time outside `isValidRecordTime` gives "", where `toISOString` would
/// throw: past 8.64e15 the millisecond arithmetic below loses precision
/// and could not be converted to an Int.
public func isoTimestamp(_ ms: Millis) -> String {
    guard isValidRecordTime(ms) else { return "" }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let whole = ms.rounded(.towardZero)
    let seconds = (whole / 1000).rounded(.down)
    // Exact here: every valid time is an integer well below 2^53.
    let millis = clamp(Int(whole - seconds * 1000), 0, 999)
    let parts = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: seconds))
    let year = astronomicalYear(era: parts.era, year: parts.year)
    let date = "\(expandedYear(year))-\(twoDigits(parts.month ?? 0))-\(twoDigits(parts.day ?? 0))"
    let time = "\(twoDigits(parts.hour ?? 0)):\(twoDigits(parts.minute ?? 0)):\(twoDigits(parts.second ?? 0)).\(threeDigits(millis))"
    return "\(date)T\(time)Z"
}

/// Gregorian era 0 is BC: its year 1 is astronomical year 0.
func astronomicalYear(era: Int?, year: Int?) -> Int {
    let year = year ?? 0
    return era == 0 ? 1 - year : year
}

/// Four digits for 0000-9999; outside that a sign and six digits, as ISO
/// 8601 expanded years and `toISOString` write them.
func expandedYear(_ year: Int) -> String {
    if (0...9999).contains(year) { return padded(year, 4) }
    return (year < 0 ? "-" : "+") + padded(abs(year), 6)
}

/// Like `expandedYear`, but later years keep plain digits, as `isoDay`
/// always wrote them.
func isoYear(_ year: Int) -> String {
    year < 0 ? "-" + padded(abs(year), 6) : padded(year, 4)
}

func twoDigits(_ value: Int) -> String { padded(value, 2) }
func threeDigits(_ value: Int) -> String { padded(value, 3) }

func padded(_ value: Int, _ width: Int) -> String {
    let digits = String(value)
    return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
}
