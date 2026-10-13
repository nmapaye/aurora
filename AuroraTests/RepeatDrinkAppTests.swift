import AuroraCore
import Foundation
import Testing
import UserNotifications
@testable import Aurora

/// Next-day drink follow-ups through AppModel and AssistantModel. The clock
/// is pinned to a fixed-offset zone where it is midday now, so a follow-up
/// due earlier today and one still ahead both exist whenever this runs.
/// Notifications go to a scripted backend: nothing reaches iOS.
@MainActor
@Suite struct RepeatDrinkAppTests {
    /// Keeps pending and delivered requests like the system does.
    @MainActor final class Backend: NotificationBackend {
        var status: UNAuthorizationStatus = .authorized
        var pending: [String: UNNotificationRequest] = [:]
        var delivered: Set<String> = []
        func authorizationStatus() async -> UNAuthorizationStatus { status }
        func requestAuthorization() async {}
        func add(_ request: UNNotificationRequest) async throws { pending[request.identifier] = request }
        func removePending(_ ids: [String]) { for id in ids { pending[id] = nil } }
        func removeDelivered(_ ids: [String]) { delivered.subtract(ids) }
        func pendingIdentifiers() async -> [String] { Array(pending.keys) }
        func deliveredIdentifiers() async -> [String] { Array(delivered) }
    }

    /// A zone where it is now between 12:00 and 13:00, without DST.
    static let zone: TimeZone = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return TimeZone(secondsFromGMT: (12 - utc.component(.hour, from: .now)) * 3600)!
    }()

    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    private func setup(_ directory: URL, backend: Backend, settings: RepeatDrinkSettings?) -> (AppModel, AssistantModel) {
        let app = AppModel(
            clock: LocalClock(timeZone: Self.zone),
            text: .localized(locale: Locale(identifier: "en_US"), timeZone: Self.zone),
            reminders: ReminderService(backend: backend, defaults: UserDefaults(suiteName: UUID().uuidString)!),
            makeStore: { StateStore(directory: directory.appendingPathComponent("records")) },
            legacy: { nil }
        )
        app.load()
        if let settings { app.setRepeatDrinks(settings) }
        let assistant = AssistantModel(
            calendars: CalendarService(providers: [], defaults: UserDefaults(suiteName: UUID().uuidString)!),
            makeStore: { ConversationStore(directory: directory) }
        )
        return (app, assistant)
    }

    /// A drink logged yesterday, `offset` from the current time of day.
    @discardableResult
    private func yesterday(_ app: AppModel, _ source: String, mg: Double, offset: Millis) -> Dose {
        app.tick()
        return app.addCustomDose(.init(mg: numberText(mg), source: source, timestamp: app.now - dayMs + offset, note: ""))
    }

    private func followUps(_ assistant: AssistantModel) -> [ConversationMessage] {
        assistant.conversation.messages.filter { $0.card?.kind == .repeatDrink }
    }

    @Test func offByDefault() async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Backend()
        let (app, assistant) = setup(directory, backend: backend, settings: nil)
        yesterday(app, "Drip", mg: 95, offset: -30 * minuteMs)
        yesterday(app, "Matcha", mg: 70, offset: 2 * hourMs)
        await assistant.start(app: app)
        #expect(followUps(assistant).isEmpty)
        #expect(backend.pending.isEmpty)
        #expect(assistant.repeatDrinkStatus == .off)
    }

    @Test func dueFollowUpIsShownOnceAndNotTodayIsKept() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Backend()
        let (app, assistant) = setup(directory, backend: backend, settings: .init(enabled: true, notify: false))
        let drip = yesterday(app, "Drip", mg: 95, offset: -30 * minuteMs)
        await assistant.start(app: app)
        let shown = followUps(assistant)
        #expect(shown.count == 1)
        let message = try #require(shown.first)
        #expect(message.card?.repeatDrink?.doseID == drip.id)
        #expect(message.card?.title.hasPrefix("Had your ") == true && message.card?.title.hasSuffix(" Drip today?") == true)
        #expect(message.card?.summary == "Yesterday · 95 mg")

        // Another foreground doesn't ask again.
        await assistant.foreground(app: app)
        #expect(followUps(assistant).count == 1)

        assistant.dismissRepeatDrink(message, app: app)
        #expect(followUps(assistant).first?.card?.state == .discarded)
        #expect(assistant.conversation.dismissedSuggestions.contains(RepeatDrinks.key(doseID: drip.id)))
        // Nothing was recorded and nothing was scheduled.
        #expect(app.state.doses.count == 1)
        #expect(backend.pending.isEmpty)

        // After a relaunch the dismissed follow-up stays answered.
        let (relaunchedApp, relaunched) = setup(directory, backend: backend, settings: nil)
        await relaunched.start(app: relaunchedApp)
        #expect(followUps(relaunched).count == 1)
        #expect(followUps(relaunched).first?.card?.state == .discarded)
    }

    @Test func reviewOpensADraftWithYesterdaysDrinkTimedNow() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Backend()
        let (app, assistant) = setup(directory, backend: backend, settings: .init(enabled: true, notify: false))
        yesterday(app, "Drip", mg: 95, offset: -30 * minuteMs)
        await assistant.start(app: app)
        let message = try #require(followUps(assistant).first)
        assistant.reviewRepeatDrink(message, app: app)
        let draft = try #require(assistant.pendingDraft)
        #expect(draft.mg == "95" && draft.source == "Drip" && draft.note.isEmpty)
        #expect(draft.timestamp <= app.now && draft.timestamp > app.now - minuteMs)
        #expect(assistant.conversation.messages.last?.card?.kind == .caffeineDraft)
        #expect(followUps(assistant).first?.card?.state == .saved)
        // Reviewing records nothing until the draft is saved.
        #expect(app.state.doses.count == 1)
    }

    @Test func notificationsCoverOnlyFollowUpsStillAheadToday() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Backend()
        let (app, assistant) = setup(directory, backend: backend, settings: .init(enabled: true, notify: true))
        yesterday(app, "Drip", mg: 95, offset: -30 * minuteMs)
        let matcha = yesterday(app, "Matcha", mg: 70, offset: 2 * hourMs)
        await assistant.start(app: app)

        // The Drip is due now, so it's in the conversation, not a notification.
        #expect(followUps(assistant).count == 1)
        let id = RepeatDrinks.notificationPrefix + matcha.id
        #expect(Set(backend.pending.keys) == [id])
        #expect(assistant.repeatDrinkStatus == .scheduled(count: 1))
        let request = try #require(backend.pending[id])
        #expect(request.content.title.hasSuffix(" Matcha today?"))
        #expect(request.content.body == "Yesterday · 70 mg")
        let planned = try #require(RepeatDrinks.planned(doses: app.state.doses, now: app.now, clock: app.clock).first { $0.doseID == matcha.id })
        let fires = try #require((request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
        #expect(abs(fires.timeIntervalSince1970 * 1000 - planned.dueAt) < 1000)

        // A matcha logged now, two hours before its time, doesn't answer it.
        app.tick()
        _ = app.addCustomDose(.init(mg: "70", source: "Matcha", timestamp: app.now, note: ""))
        await assistant.syncRepeatDrinkNotifications(app: app)
        #expect(backend.pending[id] != nil)

        // Turning notifications off removes it.
        app.setRepeatDrinks(.init(enabled: true, notify: false))
        await assistant.syncRepeatDrinkNotifications(app: app)
        #expect(backend.pending.isEmpty)
        #expect(assistant.repeatDrinkStatus == .off)
    }

    @Test func deniedPermissionSchedulesNothing() async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Backend()
        backend.status = .denied
        let (app, assistant) = setup(directory, backend: backend, settings: .init(enabled: true, notify: true))
        yesterday(app, "Matcha", mg: 70, offset: 2 * hourMs)
        await assistant.start(app: app)
        #expect(backend.pending.isEmpty)
        #expect(assistant.repeatDrinkStatus == .denied)
    }

    @Test func eraseRemovesPendingAndDeliveredFollowUps() async {
        let backend = Backend()
        let service = ReminderService(backend: backend, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let keep = UNNotificationRequest(identifier: "unrelated", content: UNMutableNotificationContent(), trigger: nil)
        let followUp = UNNotificationRequest(identifier: RepeatDrinks.notificationPrefix + "a", content: UNMutableNotificationContent(), trigger: nil)
        backend.pending = ["unrelated": keep, followUp.identifier: followUp]
        backend.delivered = ["unrelated", RepeatDrinks.notificationPrefix + "b"]
        service.cancelForErase()
        for _ in 0..<1000 where backend.pending.count > 1 || backend.delivered.count > 1 { await Task.yield() }
        #expect(Set(backend.pending.keys) == ["unrelated"])
        #expect(backend.delivered == ["unrelated"])
        // Erase's own notification sweep covers the prefix too.
        #expect(LocalDataDeletion.notificationPrefixes.contains(RepeatDrinks.notificationPrefix))
    }
}
