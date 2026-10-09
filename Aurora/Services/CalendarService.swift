import AuroraCore
import EventKit
import Foundation
import Observation

@MainActor
protocol CommitmentProvider {
    var providerID: CalendarProviderID { get }
    func calendars() async throws -> [AssistantCalendar]
    func events(calendarIDs: [String], from: Date, to: Date) async throws -> [Commitment]
    func current(_ event: Commitment) async throws -> Commitment
    func move(_ change: CalendarChange) async throws -> Commitment
}

@MainActor
final class AppleCalendarProvider: CommitmentProvider {
    let providerID = CalendarProviderID.apple
    private let store = EKEventStore()
    var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    func connect() async throws {
        guard try await store.requestFullAccessToEvents() else { throw CalendarActionError.unavailable }
    }
    func calendars() async throws -> [AssistantCalendar] {
        guard authorized else { return [] }
        return store.calendars(for: .event).map { .init(id: $0.calendarIdentifier, provider: .apple, title: "\($0.title) · \($0.source.title)", writable: $0.allowsContentModifications) }
    }
    func events(calendarIDs: [String], from: Date, to: Date) async throws -> [Commitment] {
        guard authorized else { throw CalendarActionError.unavailable }
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: calendars)).compactMap(commitment)
    }
    private func commitment(_ event: EKEvent) -> Commitment? {
        guard let id = event.eventIdentifier, let calendar = event.calendar, let start = event.startDate, let end = event.endDate else { return nil }
        let canMove = calendar.allowsContentModifications && !event.isAllDay && (event.attendees?.isEmpty ?? true) && (event.organizer == nil || event.organizer?.isCurrentUser == true)
        return .init(id: id, calendarID: calendar.calendarIdentifier, provider: .apple, title: event.title ?? "Untitled event", start: start, end: end,
            timeZone: event.timeZone?.identifier ?? TimeZone.current.identifier,
            revision: "\(event.lastModifiedDate?.timeIntervalSince1970 ?? 0)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)", canMove: canMove, recurring: event.hasRecurrenceRules || event.isDetached)
    }
    private func occurrence(_ original: Commitment) throws -> EKEvent {
        guard authorized, let calendar = store.calendar(withIdentifier: original.calendarID) else { throw CalendarActionError.unavailable }
        store.refreshSourcesIfNecessary()
        let predicate = store.predicateForEvents(withStart: original.start.addingTimeInterval(-1), end: original.end.addingTimeInterval(1), calendars: [calendar])
        guard let event = store.events(matching: predicate).first(where: { $0.eventIdentifier == original.id && $0.startDate == original.start }) else { throw CalendarActionError.stale }
        return event
    }
    func current(_ event: Commitment) async throws -> Commitment {
        guard let value = commitment(try occurrence(event)) else { throw CalendarActionError.unavailable }
        return value
    }
    func move(_ change: CalendarChange) async throws -> Commitment {
        let event = try occurrence(change.original)
        guard commitment(event) == change.original else { throw CalendarActionError.stale }
        event.startDate = change.newStart; event.endDate = change.newEnd
        try store.save(event, span: .thisEvent, commit: true)
        guard let result = commitment(event) else { throw CalendarActionError.unavailable }
        return result
    }
}

@MainActor
@Observable
final class CalendarService {
    let apple = AppleCalendarProvider()
    let google = GoogleCalendarProvider()
    private let defaults: UserDefaults
    private var providers: [any CommitmentProvider] = []
    var calendars: [AssistantCalendar] = []
    var commitments: [Commitment] = []
    var message: String?
    var loading = false
    var selected: Set<String> {
        didSet { defaults.set(Array(selected), forKey: "assistant.selectedCalendars") }
    }
    var mirrorAuthority: [String: String] {
        didSet { defaults.set(mirrorAuthority, forKey: "assistant.calendarMirrorAuthority") }
    }
    private var consumedApprovals: Set<UUID> = []
    private var generation = 0
    func resetAfterErase() {
        generation += 1
        google.forgetLocalSession()
        selected = []; mirrorAuthority = [:]
        defaults.removeObject(forKey: "assistant.selectedCalendars")
        defaults.removeObject(forKey: "assistant.calendarMirrorAuthority")
        calendars = []; commitments = []; consumedApprovals = []
        message = nil; loading = false
    }
    init(providers: [any CommitmentProvider]? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selected = Set(defaults.stringArray(forKey: "assistant.selectedCalendars") ?? [])
        mirrorAuthority = defaults.dictionary(forKey: "assistant.calendarMirrorAuthority") as? [String: String] ?? [:]
        selected = Set(selected.filter { mirrorAuthority[$0] == nil || mirrorAuthority[$0] == $0 })
        self.providers = providers ?? [apple, google]
    }
    func key(_ calendar: AssistantCalendar) -> String { "\(calendar.provider.rawValue):\(calendar.id)" }
    func toggle(_ calendar: AssistantCalendar) {
        let id = key(calendar)
        if selected.contains(id) { selected.remove(id) }
        else { selected.insert(mirrorAuthority[id] ?? id) }
        commitments = []
    }
    func linkMirror(appleID: String, googleID: String, authority: CalendarProviderID) {
        let appleKey = "apple:\(appleID)", googleKey = "google:\(googleID)"
        let canonical = authority == .apple ? appleKey : googleKey
        mirrorAuthority[appleKey] = canonical; mirrorAuthority[googleKey] = canonical
        selected.remove(appleKey); selected.remove(googleKey); selected.insert(canonical)
        commitments = []
    }
    func refreshCalendars() async {
        let currentGeneration = generation
        calendars = []; var failures: [String] = []
        for provider in providers {
            do {
                let result = try await provider.calendars()
                guard generation == currentGeneration else { return }
                calendars += result
            }
            catch { guard generation == currentGeneration else { return }; failures.append(provider.providerID.rawValue.capitalized) }
        }
        message = failures.isEmpty ? nil : "Calendar access needs attention: \(failures.joined(separator: ", "))."
    }
    func refresh(from: Date = .now) async {
        let currentGeneration = generation
        loading = true; defer { if generation == currentGeneration { loading = false } }
        commitments = []
        let start = Calendar.current.startOfDay(for: from)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        var failures: [String] = selected.subtracting(Set(calendars.map(key))).isEmpty ? [] : ["unavailable selected calendars"]
        for provider in providers {
            let ids = calendars.filter { $0.provider == provider.providerID && selected.contains(key($0)) }.map(\.id)
            guard !ids.isEmpty else { continue }
            do {
                let result = try await provider.events(calendarIDs: ids, from: start, to: end)
                guard generation == currentGeneration else { return }
                commitments += result
            }
            catch { guard generation == currentGeneration else { return }; failures.append(provider.providerID.rawValue.capitalized) }
        }
        commitments.sort { $0.start < $1.start }
        message = failures.isEmpty ? nil : "Couldn't refresh \(failures.joined(separator: ", ")). Changes are blocked until all selected calendars refresh."
    }
    func approve(_ change: CalendarChange) async throws -> Commitment {
        let currentGeneration = generation
        guard !consumedApprovals.contains(change.id), selected.contains("\(change.original.provider.rawValue):\(change.original.calendarID)") else { throw CalendarActionError.approvalRequired }
        consumedApprovals.insert(change.id)
        await refresh(from: change.newStart)
        guard message == nil else { throw CalendarActionError.unavailable }
        guard let provider = providers.first(where: { $0.providerID == change.original.provider }) else { throw CalendarActionError.unavailable }
        let current = try await provider.current(change.original)
        guard generation == currentGeneration else { throw CalendarActionError.approvalRequired }
        try CalendarActionValidator.validate(change, current: current, approvedID: change.id, now: .now, others: commitments)
        let result = try await provider.move(change)
        await refresh()
        return result
    }
}
