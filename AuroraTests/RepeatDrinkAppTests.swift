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
        // Asked an hour after yesterday's time, so 90 minutes ago is due now.
        let drip = yesterday(app, "Drip", mg: 95, offset: -90 * minuteMs)
        await assistant.start(app: app)
        let shown = followUps(assistant)
        #expect(shown.count == 1)
        let message = try #require(shown.first)
        #expect(message.card?.repeatDrink?.doseID == drip.id)
        #expect(message.card?.title.hasPrefix("Did you have a Drip around ") == true && message.card?.title.hasSuffix("?") == true)
        #expect(message.card?.summary == "Yesterday · 95 mg")

        // Another foreground doesn't ask again.
        await assistant.foreground(app: app)
        #expect(followUps(assistant).count == 1)

        assistant.dismissRepeatDrink(message, app: app)
        #expect(followUps(assistant).first?.card?.state == .discarded)
        #expect(assistant.conversation.dismissedSuggestions.contains(RepeatDrinks.key(doseID: drip.id)))
        // "Not today" records nothing, never a zero, and schedules nothing.
        #expect(app.state.doses.count == 1 && !app.state.doses.contains { $0.mg == 0 })
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
        yesterday(app, "Drip", mg: 95, offset: -90 * minuteMs)
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

    @Test func oneSilentNotificationWithoutAmountsAnHourAfterYesterdaysTime() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Backend()
        let (app, assistant) = setup(directory, backend: backend, settings: .init(enabled: true, notify: true))
        yesterday(app, "Drip", mg: 95, offset: -90 * minuteMs)
        let matcha = yesterday(app, "Matcha", mg: 70, offset: 2 * hourMs)
        let cola = yesterday(app, "Cola", mg: 40, offset: 2 * hourMs + 30 * minuteMs)
        await assistant.start(app: app)

        // The Drip is due now, so it's in the conversation, not a notification.
        #expect(followUps(assistant).count == 1)
        // The two still ahead share one notification.
        #expect(backend.pending.count == 1)
        let (id, request) = try #require(backend.pending.first)
        #expect(id.hasPrefix(RepeatDrinks.notificationPrefix))
        #expect(assistant.repeatDrinkStatus == .scheduled(count: 2))
        #expect(request.content.title == "Log yesterday’s drinks?")
        #expect(request.content.body == "Matcha · around \(app.text.clockTime(matcha.timestamp)).\nCola · around \(app.text.clockTime(cola.timestamp)).")
        #expect(!request.content.body.contains("mg") && !request.content.title.contains("mg"))
        #expect(request.content.interruptionLevel == .passive && request.content.sound == nil)
        // At the later due time, an hour after yesterday's cola.
        let planned = try #require(RepeatDrinks.planned(doses: app.state.doses, now: app.now, clock: app.clock).first { $0.doseID == cola.id })
        #expect(planned.dueAt == planned.sameTimeAt + hourMs)
        let fires = try #require((request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
        #expect(abs(fires.timeIntervalSince1970 * 1000 - planned.dueAt) < 60_000)

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

    @Test func theMorningBriefingUsesAurorasOneNotification() async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Backend()
        let (app, assistant) = setup(directory, backend: backend, settings: .init(enabled: true, notify: true))
        yesterday(app, "Matcha", mg: 70, offset: 2 * hourMs)
        await assistant.start(app: app)
        #expect(backend.pending.count == 1)
        assistant.conversation.preferences.proactive = true
        assistant.conversation.preferences.morningBriefing = true
        assistant.conversation.preferences.quietStartHour = 22
        assistant.conversation.preferences.quietEndHour = 6
        assistant.conversation.preferences.briefingHour = 7
        await assistant.syncRepeatDrinkNotifications(app: app)
        #expect(backend.pending.isEmpty)
        #expect(assistant.repeatDrinkStatus == .off)
        // The follow-up still appears in the conversation when it's due.
        #expect(RepeatDrinks.upcoming(RepeatDrinks.planned(doses: app.state.doses, now: app.now, clock: app.clock), conversation: assistant.conversation, now: app.now, clock: app.clock).count == 1)
        assistant.conversation.preferences.morningBriefing = false
        await assistant.syncRepeatDrinkNotifications(app: app)
        #expect(backend.pending.count == 1)
    }

    @Test func noFollowUpAtOrAfterTheirCutoffTime() async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Backend()
        let (app, assistant) = setup(directory, backend: backend, settings: .init(enabled: true, notify: true))
        // Asked about three hours from now, after a cutoff two hours ahead.
        yesterday(app, "Matcha", mg: 70, offset: 2 * hourMs)
        await app.setCutoffHour(Double(app.clock.hour(app.now) + 2))
        await assistant.start(app: app)
        #expect(backend.pending.isEmpty)
        #expect(assistant.repeatDrinkStatus == .scheduled(count: 0))
        await app.setCutoffHour(nil)
        await assistant.syncRepeatDrinkNotifications(app: app)
        #expect(backend.pending.count == 1)
    }

    @Test func notificationsPauseAfterFiveUnansweredDaysAndResume() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Backend()
        let (app, assistant) = setup(directory, backend: backend, settings: .init(enabled: true, notify: true))
        yesterday(app, "Matcha", mg: 70, offset: 2 * hourMs)
        await assistant.start(app: app)
        #expect(backend.pending.count == 1 && !assistant.repeatDrinksPaused)
        // Five earlier days with a follow-up offered and none answered.
        let today = app.clock.startOfDay(app.now)
        var engagement = RepeatDrinks.Engagement()
        for back in 1...5 {
            let day = app.clock.addingDays(-back, to: today)
            let due = app.clock.setTime(day, hour: 10)
            engagement.recordOffered([.init(doseID: "old-\(back)", source: "Tea", mg: 30, yesterdayAt: due - dayMs - hourMs, dueAt: due)], now: due, clock: app.clock)
        }
        assistant.conversation.repeatDrinkEngagement = engagement
        await assistant.syncRepeatDrinkNotifications(app: app)
        #expect(backend.pending.isEmpty && assistant.repeatDrinksPaused)
        #expect(assistant.repeatDrinkStatus == .off)
        // Turning notifications on again resumes them.
        assistant.resumeRepeatDrinkNotifications()
        await assistant.syncRepeatDrinkNotifications(app: app)
        #expect(backend.pending.count == 1 && !assistant.repeatDrinksPaused)
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
