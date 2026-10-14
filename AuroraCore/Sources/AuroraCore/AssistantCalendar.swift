import Foundation

public enum CalendarProviderID: String, Codable, Sendable { case apple, google }

public struct AssistantCalendar: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var provider: CalendarProviderID
    public var title: String
    public var writable: Bool
    public init(id: String, provider: CalendarProviderID, title: String, writable: Bool) {
        self.id = id; self.provider = provider; self.title = title; self.writable = writable
    }
}

public struct Commitment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var calendarID: String
    public var provider: CalendarProviderID
    public var title: String
    public var start: Date
    public var end: Date
    public var timeZone: String
    public var revision: String
    public var canMove: Bool
    public var recurring: Bool
    // Display details, absent in snapshots from older builds.
    public var location: String?
    /// The calendar's own color, "#RRGGBB".
    public var colorHex: String?
    /// When the source last changed the event; the newest copy wins when
    /// the same event comes from both Apple and Google.
    public var lastModified: Date?
    public var allDay: Bool?
    public init(id: String, calendarID: String, provider: CalendarProviderID, title: String, start: Date, end: Date, timeZone: String, revision: String, canMove: Bool, recurring: Bool,
                location: String? = nil, colorHex: String? = nil, lastModified: Date? = nil, allDay: Bool? = nil) {
        self.id = id; self.calendarID = calendarID; self.provider = provider; self.title = title
        self.start = start; self.end = end; self.timeZone = timeZone; self.revision = revision; self.canMove = canMove; self.recurring = recurring
        self.location = location; self.colorHex = colorHex; self.lastModified = lastModified; self.allDay = allDay
    }
    public var identity: String { "\(provider.rawValue):\(calendarID):\(id):\(start.timeIntervalSince1970)" }
}

public struct CalendarChange: Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var original: Commitment
    public var newStart: Date
    public var newEnd: Date
    public init(original: Commitment, newStart: Date, newEnd: Date) {
        self.original = original; self.newStart = newStart; self.newEnd = newEnd
    }
}

public enum CalendarActionError: Error, Equatable, Sendable {
    case approvalRequired, stale, readOnly, invalidTime, conflict, unavailable
}

public enum CalendarActionValidator {
    public static func validate(_ change: CalendarChange, current: Commitment, approvedID: UUID?, now: Date, others: [Commitment]) throws {
        guard approvedID == change.id else { throw CalendarActionError.approvalRequired }
        guard current == change.original else { throw CalendarActionError.stale }
        guard current.canMove else { throw CalendarActionError.readOnly }
        guard change.newStart.timeIntervalSince1970.isFinite, change.newEnd.timeIntervalSince1970.isFinite,
              change.newStart >= now, change.newEnd > change.newStart,
              abs(change.newEnd.timeIntervalSince(change.newStart) - current.end.timeIntervalSince(current.start)) < 1 else { throw CalendarActionError.invalidTime }
        guard !others.contains(where: { $0.identity != current.identity && $0.start < change.newEnd && $0.end > change.newStart }) else { throw CalendarActionError.conflict }
    }

    /// Suggest the earliest conflict-free slot after the original, within the same local day.
    public static func proposedMove(_ event: Commitment, among events: [Commitment], now: Date, calendar: Calendar) -> CalendarChange? {
        guard event.canMove, event.start >= now else { return nil }
        let duration = event.end.timeIntervalSince(event.start)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: event.start))!
        var start = event.start.addingTimeInterval(30 * 60)
        while start.addingTimeInterval(duration) <= dayEnd {
            let end = start.addingTimeInterval(duration)
            if !events.contains(where: { $0.identity != event.identity && $0.start < end && $0.end > start }) {
                return CalendarChange(original: event, newStart: start, newEnd: end)
            }
            start = start.addingTimeInterval(15 * 60)
        }
        return nil
    }
}

/// One copy of each event when Apple and Google both deliver it (for
/// example a Google calendar also added to the iPhone's Calendar app).
/// What the calendar card lists: what's left of today, without sleep and
/// routine blocks, which aren't commitments to plan around.
public enum CalendarAgenda {
    /// A title word starting with one of these marks a sleep or routine
    /// block ("In Bed and Asleep", "Stop Naps", "Morning Pills"). Matching
    /// word starts keeps "Snapshot review" visible.
    public static let routineWords = ["asleep", "sleep", "bed", "nap", "routine", "pills", "meds"]

    public static func isRoutine(_ title: String) -> Bool {
        let words = title.lowercased().split { !$0.isLetter }
        return words.contains { word in routineWords.contains { word.hasPrefix($0) } }
    }

    /// Events not yet ended that start before tomorrow, routines left out,
    /// earliest first.
    public static func restOfToday(_ events: [Commitment], now: Date, calendar: Calendar) -> [Commitment] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return events
            .filter { $0.end > now && $0.start < tomorrow && !isRoutine($0.title) }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }
    }

    /// The briefing's short list: the first few of `restOfToday`.
    public static let briefingLimit = 3

    public static func briefing(_ events: [Commitment], now: Date, calendar: Calendar) -> [Commitment] {
        Array(restOfToday(events, now: now, calendar: calendar).prefix(briefingLimit))
    }

    /// Identities of timed events that overlap another timed event in
    /// `events`. Only these offer a later slot.
    public static func clashing(_ events: [Commitment]) -> Set<String> {
        let timed = events.filter { $0.allDay != true }
        var result = Set<String>()
        for (index, event) in timed.enumerated() {
            for other in timed[(index + 1)...] where other.start < event.end && event.start < other.end {
                result.insert(event.identity)
                result.insert(other.identity)
            }
        }
        return result
    }

    /// Source labels only help when the list mixes providers.
    public static func showsSource(_ events: [Commitment]) -> Bool {
        Set(events.map(\.provider)).count > 1
    }

    /// A timed event that ends on a later calendar day than it starts.
    public static func endsNextDay(_ event: Commitment, calendar: Calendar) -> Bool {
        event.allDay != true && !calendar.isDate(event.start, inSameDayAs: event.end.addingTimeInterval(-1))
    }
}

public enum CalendarMerge {
    /// Events from different providers with the same title (ignoring case and
    /// spacing), start and end are the same event; the most recently changed
    /// copy is kept, and an unknown change time counts as oldest. Events from
    /// one provider are never merged with each other.
    public static func newestCopies(_ events: [Commitment]) -> [Commitment] {
        func key(_ event: Commitment) -> String {
            let title = event.title.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return "\(title)|\(Int(event.start.timeIntervalSince1970))|\(Int(event.end.timeIntervalSince1970))"
        }
        var kept: [String: Commitment] = [:]
        var order: [String] = []
        var result: [Commitment] = []
        for event in events {
            let match = key(event)
            guard let existing = kept[match] else {
                kept[match] = event; order.append(match); continue
            }
            if existing.provider == event.provider {
                // Same provider: genuinely separate events that look alike.
                result.append(event)
                continue
            }
            let newer = (event.lastModified ?? .distantPast) > (existing.lastModified ?? .distantPast)
            if newer { kept[match] = event }
        }
        return (order.compactMap { kept[$0] } + result).sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }
}
