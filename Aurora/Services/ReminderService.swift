import AuroraCore
import Foundation
import UserNotifications

/// Local notifications: a daily reminder at the user's own cutoff hour, at
/// most one one-off cutoff scenario reminder the person saved, and the
/// caffeine reminders they set relative to waking. Every sync cancels first
/// and schedules again only when switched on and allowed.
///
/// Daily syncs run one at a time, in the order they were asked for, and a
/// sync that a newer one has superseded does not schedule. So a foreground
/// refresh that overlaps a change in Settings can't leave the reminder on
/// after it was switched off.
@MainActor
final class ReminderService {
    enum Status: Equatable {
        case off
        case scheduled(hour: Int)
        case denied
        /// Allowed, but the system refused to schedule it.
        case failed
    }

    private let center: any NotificationBackend
    private let clock: () -> LocalClock
    private let text: () -> DateText
    private let defaults: UserDefaults
    private var generation = 0

    init(
        backend: (any NotificationBackend)? = nil,
        clock: @escaping () -> LocalClock = { .current },
        text: @escaping () -> DateText = { .current },
        defaults: UserDefaults = .standard
    ) {
        center = backend ?? LiveNotificationBackend()
        self.clock = clock
        self.text = text
        self.defaults = defaults
    }

    /// Removes notifications on the same serial queue as every other call
    /// Aurora makes, and returns once the removal has run.
    nonisolated static func remove(pending: [String] = [], delivered: [String] = []) async {
        await LiveNotificationBackend.remove(pending: pending, delivered: delivered)
    }

    func cancelForErase() {
        generation += 1
        wakeGeneration += 1
        let ids = [CutoffReminder.identifier, CutoffScenario.reminderIdentifier]
        center.removePending(ids)
        center.removeDelivered(ids)
        Task { await removeWake(delivered: true); await removeRepeatDrinks(delivered: true) }
        defaults.removeObject(forKey: Self.wakeScheduleKey)
    }

    // MARK: Cutoff scenario

    enum ScenarioOutcome: Equatable { case scheduled, notAllowed, failed }

    /// One reminder at a cutoff scenario's instant, apart from the daily
    /// cutoff reminder, which it never changes. Never asks for permission.
    /// A fixed identifier means a repeated Save replaces, never duplicates.
    /// Writes run one at a time in the order Save was tapped, so an older
    /// Save can never land after, and replace, a newer one.
    /// The erase generation is taken when Save is tapped, so a write queued
    /// before an erase never reaches the notification center after it.
    func scheduleScenario(_ content: CutoffScenario.ReminderContent) async -> ScenarioOutcome {
        let previous = scenarioWrites
        let enqueued = generation
        let write = Task { @MainActor in
            await previous?.value
            return await self.writeScenario(content, generation: enqueued)
        }
        scenarioWrites = Task { _ = await write.value }
        return await write.value
    }

    private var scenarioWrites: Task<Void, Never>?

    private func writeScenario(_ content: CutoffScenario.ReminderContent, generation currentGeneration: Int) async -> ScenarioOutcome {
        guard generation == currentGeneration else { return .failed }
        let status = await center.authorizationStatus()
        guard generation == currentGeneration else { return .failed }
        guard [.authorized, .provisional, .ephemeral].contains(status) else { return .notAllowed }
        // An interval from now fires at the absolute instant, whatever the
        // wall clock does in between.
        let interval = content.fireAt / 1000 - Date.now.timeIntervalSince1970
        guard interval >= 1 else { return .failed }
        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: CutoffScenario.reminderIdentifier, content: notification, trigger: trigger))
            // Erased while adding. Later writes wait for this one, so this
            // removal can only reach this write's own request.
            guard generation == currentGeneration else {
                center.removePending([CutoffScenario.reminderIdentifier])
                return .failed
            }
            return .scheduled
        } catch {
            return .failed
        }
    }

    // MARK: Wake reminders

    enum WakeStatus: Equatable {
        case off
        case scheduled(next: Millis?)
        case denied
    }

    private var wakeGeneration = 0
    /// Ids and fire times last handed to the system, so a reminder whose time
    /// has passed counts as delivered even after its banner is cleared.
    static let wakeScheduleKey = "aurora.wakeReminders.scheduled"

    /// Ids of wake reminders already shown, from the system's delivered list
    /// and from earlier schedules whose time has passed.
    func deliveredWakeIDs(now: Millis) async -> Set<String> {
        let shown = await center.deliveredIdentifiers().filter { $0.hasPrefix(WakeReminders.identifierPrefix) }
        let scheduled = defaults.dictionary(forKey: Self.wakeScheduleKey) as? [String: Double] ?? [:]
        return Set(shown).union(scheduled.filter { $0.value <= now }.map(\.key))
    }

    /// Replaces every pending wake reminder with `reminders`. Never prompts
    /// unless `prompt` is set (only from Save in settings).
    func syncWake(_ reminders: [WakeReminders.Reminder], enabled: Bool, now: Millis, prompt: Bool) async -> WakeStatus {
        wakeGeneration += 1
        let current = wakeGeneration
        await removeWake(delivered: false)
        guard enabled else {
            defaults.removeObject(forKey: Self.wakeScheduleKey)
            return .off
        }
        var status = await center.authorizationStatus()
        if status == .notDetermined && prompt {
            await center.requestAuthorization()
            status = await center.authorizationStatus()
        }
        guard current == wakeGeneration else { return .off }
        switch status {
        case .authorized, .provisional, .ephemeral: break
        default: return .denied
        }
        // Keep passed entries so they still count as delivered today.
        var record = (defaults.dictionary(forKey: Self.wakeScheduleKey) as? [String: Double] ?? [:]).filter { $0.value <= now && $0.value > now - 2 * dayMs }
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let date = Date(timeIntervalSince1970: reminder.fireAt / 1000)
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date),
                repeats: false
            )
            do {
                try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
                record[reminder.id] = reminder.fireAt
            } catch {
                continue
            }
            guard current == wakeGeneration else {
                await removeWake(delivered: false)
                return .off
            }
        }
        defaults.set(record, forKey: Self.wakeScheduleKey)
        return .scheduled(next: reminders.map(\.fireAt).min())
    }

    private func removeWake(delivered: Bool) async {
        let pending = await center.pendingIdentifiers().filter { $0.hasPrefix(WakeReminders.identifierPrefix) }
        if !pending.isEmpty { center.removePending(pending) }
        if delivered {
            let shown = await center.deliveredIdentifiers().filter { $0.hasPrefix(WakeReminders.identifierPrefix) }
            if !shown.isEmpty { center.removeDelivered(shown) }
        }
    }

    // MARK: Drink follow-ups

    enum RepeatDrinkStatus: Equatable {
        case off
        case scheduled(count: Int)
        case denied
    }

    private var repeatGeneration = 0

    /// Replaces every pending follow-up notification with today's one
    /// `batch`: silent (`.passive`, no sound), with no amounts. Never
    /// prompts for permission unless `prompt` is set (only when the person
    /// turns notifications on). `enabled` is false when follow-up
    /// notifications are off, paused, or give way to the briefing under
    /// `NotificationBudget`.
    func syncRepeatDrinks(_ batch: RepeatDrinks.Batch?, enabled: Bool, prompt: Bool, text: DateText) async -> RepeatDrinkStatus {
        repeatGeneration += 1
        let current = repeatGeneration
        await removeRepeatDrinks(delivered: false)
        guard enabled else { return .off }
        var status = await center.authorizationStatus()
        if status == .notDetermined && prompt {
            await center.requestAuthorization()
            status = await center.authorizationStatus()
        }
        guard current == repeatGeneration else { return .off }
        guard [.authorized, .provisional, .ephemeral].contains(status) else { return .denied }
        guard let batch, !batch.prompts.isEmpty else { return .scheduled(count: 0) }
        let content = UNMutableNotificationContent()
        content.title = RepeatDrinks.notificationTitle
        content.body = RepeatDrinks.notificationBody(batch, text: text)
        content.sound = nil
        content.interruptionLevel = .passive
        let date = Date(timeIntervalSince1970: batch.fireAt / 1000)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false
        )
        do {
            try await center.add(UNNotificationRequest(identifier: batch.identifier, content: content, trigger: trigger))
        } catch { return .scheduled(count: 0) }
        guard current == repeatGeneration else {
            await removeRepeatDrinks(delivered: false)
            return .off
        }
        return .scheduled(count: batch.prompts.count)
    }

    private func removeRepeatDrinks(delivered: Bool) async {
        let pending = await center.pendingIdentifiers().filter { $0.hasPrefix(RepeatDrinks.notificationPrefix) }
        if !pending.isEmpty { center.removePending(pending) }
        if delivered {
            let shown = await center.deliveredIdentifiers().filter { $0.hasPrefix(RepeatDrinks.notificationPrefix) }
            if !shown.isEmpty { center.removeDelivered(shown) }
        }
    }

    // MARK: Daily cutoff reminder

    /// How many daily syncs have been asked for. Tests wait on it.
    private(set) var latestIntent = 0
    private var promptingSyncs = 0
    private var dailySyncs: Task<Void, Never>?
    private(set) var lastStatus: Status = .off

    /// `prompt` asks for permission when it hasn't been decided yet. Only
    /// Settings passes `true`; foreground syncs never prompt, and one that
    /// arrives while a prompting sync is open reports the last status rather
    /// than racing the permission sheet.
    /// With no cutoff time set there is nothing to schedule: the reminder
    /// is off whatever `enabled` says.
    func sync(enabled: Bool, cutoffHour: Double?, prompt: Bool) async -> Status {
        if !prompt && promptingSyncs > 0 { return lastStatus }
        latestIntent += 1
        let intent = latestIntent
        if prompt { promptingSyncs += 1 }
        let previous = dailySyncs
        let run = Task { @MainActor in
            await previous?.value
            return await self.applyDaily(enabled: enabled, cutoffHour: cutoffHour, prompt: prompt, intent: intent)
        }
        dailySyncs = Task { _ = await run.value }
        let status = await run.value
        if prompt { promptingSyncs -= 1 }
        return status
    }

    private func applyDaily(enabled: Bool, cutoffHour: Double?, prompt: Bool, intent: Int) async -> Status {
        let currentGeneration = generation
        center.removePending([CutoffReminder.identifier])
        guard enabled, let cutoffHour, cutoffHour.isFinite, intent == latestIntent else { return finish(.off) }

        var status = await center.authorizationStatus()
        if status == .notDetermined && prompt {
            await center.requestAuthorization()
            status = await center.authorizationStatus()
        }
        guard generation == currentGeneration, intent == latestIntent else { return finish(.off) }
        switch status {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return finish(.denied)
        }

        let content = CutoffReminder.content(cutoffHour: cutoffHour, clock: clock(), text: text())
        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.sound = .default
        var components = DateComponents()
        components.hour = content.hour
        components.minute = content.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: CutoffReminder.identifier, content: notification, trigger: trigger)
        do {
            try await center.add(request)
            guard generation == currentGeneration, intent == latestIntent else {
                center.removePending([CutoffReminder.identifier])
                return finish(.off)
            }
            return finish(.scheduled(hour: content.hour))
        } catch {
            return finish(.failed)
        }
    }

    private func finish(_ status: Status) -> Status {
        lastStatus = status
        return status
    }
}

/// The notification calls Aurora makes, so tests can run the service against
/// a controlled backend that never reaches iOS.
@MainActor
protocol NotificationBackend: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async
    func add(_ request: UNNotificationRequest) async throws
    func removePending(_ ids: [String])
    func removeDelivered(_ ids: [String])
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
}

/// Every call goes through one serial queue off the main thread. Removal is
/// a synchronous XPC round trip that blocked the main thread for minutes on
/// a freshly booted simulator (spindump: `foregroundSync → sync →
/// removePendingNotificationRequests → xpc_connection_send_message_with_reply_sync`).
/// One queue, shared by every instance and by erase, keeps calls in the
/// order Aurora made them, so a removal requested before an add can never
/// land after it.
final class LiveNotificationBackend: NotificationBackend {
    nonisolated static let queue = DispatchQueue(label: "com.nmapaye.aurora.notifications", qos: .userInitiated)
    private let center = UNUserNotificationCenter.current()
    private var queue: DispatchQueue { Self.queue }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let center = center
        return await withCheckedContinuation { continuation in
            queue.async { center.getNotificationSettings { continuation.resume(returning: $0.authorizationStatus) } }
        }
    }
    func requestAuthorization() async {
        let center = center
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { center.requestAuthorization(options: [.alert, .sound]) { _, _ in continuation.resume() } }
        }
    }
    func add(_ request: UNNotificationRequest) async throws {
        let center = center
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                center.add(request) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }
    }
    func removePending(_ ids: [String]) {
        let center = center
        queue.async { center.removePendingNotificationRequests(withIdentifiers: ids) }
    }
    func removeDelivered(_ ids: [String]) {
        let center = center
        queue.async { center.removeDeliveredNotifications(withIdentifiers: ids) }
    }
    func pendingIdentifiers() async -> [String] {
        let center = center
        return await withCheckedContinuation { continuation in
            queue.async { center.getPendingNotificationRequests { continuation.resume(returning: $0.map(\.identifier)) } }
        }
    }
    func deliveredIdentifiers() async -> [String] {
        let center = center
        return await withCheckedContinuation { continuation in
            queue.async { center.getDeliveredNotifications { continuation.resume(returning: $0.map(\.request.identifier)) } }
        }
    }

    /// Removes on the shared queue and returns once the removal has run.
    nonisolated static func remove(pending: [String], delivered: [String]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                let center = UNUserNotificationCenter.current()
                if !pending.isEmpty { center.removePendingNotificationRequests(withIdentifiers: pending) }
                if !delivered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: delivered) }
                continuation.resume()
            }
        }
    }

    /// For erase: removes `ids` and every pending or delivered notification
    /// whose identifier starts with one of `prefixes`, then calls `done` on
    /// the queue. Nothing waits on the main thread.
    nonisolated static func removeAll(ids: [String], prefixes: [String], then done: @escaping @Sendable () -> Void) {
        queue.async {
            let center = UNUserNotificationCenter.current()
            let matching: @Sendable (String) -> Bool = { id in prefixes.contains { id.hasPrefix($0) } }
            center.getPendingNotificationRequests { pending in
                center.getDeliveredNotifications { delivered in
                    queue.async {
                        center.removePendingNotificationRequests(withIdentifiers: ids + pending.map(\.identifier).filter(matching))
                        center.removeDeliveredNotifications(withIdentifiers: ids + delivered.map(\.request.identifier).filter(matching))
                        done()
                    }
                }
            }
        }
    }
}
