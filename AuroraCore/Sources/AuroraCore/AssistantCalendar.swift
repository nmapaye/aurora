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
    public init(id: String, calendarID: String, provider: CalendarProviderID, title: String, start: Date, end: Date, timeZone: String, revision: String, canMove: Bool, recurring: Bool) {
        self.id = id; self.calendarID = calendarID; self.provider = provider; self.title = title
        self.start = start; self.end = end; self.timeZone = timeZone; self.revision = revision; self.canMove = canMove; self.recurring = recurring
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
