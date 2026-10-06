import AuroraCore
import Foundation
import UserNotifications

/// The calls ReminderService makes on the notification center, so tests can
/// stand in for it.
@MainActor
protocol NotificationScheduling {
    func removePending(identifiers: [String])
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async
    func add(_ request: UNNotificationRequest) async throws
}

struct SystemNotificationCenter: NotificationScheduling {
    func removePending(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }
}

/// The one local notification: a daily reminder at the user's own cutoff
/// hour, under the identifier the React Native build used, so a reminder it
/// scheduled is replaced rather than doubled. Every sync cancels it first and
/// schedules it again only when it is switched on and allowed.
///
/// Syncs run one at a time, in the order they were asked for, and a sync
/// that a newer one has superseded does not schedule. So a foreground refresh
/// that overlaps a change in Settings can't leave the reminder on after it
/// was switched off.
@MainActor
final class ReminderService {
    enum Status: Equatable {
        case off
        case scheduled(hour: Int)
        case denied
        /// Allowed, but the system refused to schedule it.
        case failed
    }

    private let center: NotificationScheduling
    private let clock: () -> LocalClock
    private let text: () -> DateText
    /// How many syncs have been asked for. Tests wait on it.
    private(set) var latestIntent = 0
    private var promptingSyncs = 0
    private var queue: Task<Void, Never>?
    private(set) var lastStatus: Status = .off

    init(
        center: NotificationScheduling? = nil,
        clock: @escaping () -> LocalClock = { .current },
        text: @escaping () -> DateText = { .current }
    ) {
        self.center = center ?? SystemNotificationCenter()
        self.clock = clock
        self.text = text
    }

    /// `prompt` asks for permission when it hasn't been decided yet. Only
    /// Settings passes `true`; foreground syncs never prompt, and stand aside
    /// while a prompting sync is in flight, since the permission sheet itself
    /// makes the app inactive and active again.
    func sync(enabled: Bool, cutoffHour: Double, prompt: Bool) async -> Status {
        if !prompt && promptingSyncs > 0 { return lastStatus }
        latestIntent += 1
        let intent = latestIntent
        if prompt { promptingSyncs += 1 }
        let previous = queue
        let run = Task { @MainActor in
            await previous?.value
            return await self.apply(enabled: enabled, cutoffHour: cutoffHour, prompt: prompt, intent: intent)
        }
        queue = Task { _ = await run.value }
        let status = await run.value
        if prompt { promptingSyncs -= 1 }
        return status
    }

    private func apply(enabled: Bool, cutoffHour: Double, prompt: Bool, intent: Int) async -> Status {
        center.removePending(identifiers: [CutoffReminder.identifier])
        guard enabled, intent == latestIntent else { return finish(.off) }

        var status = await center.authorizationStatus()
        if status == .notDetermined && prompt {
            await center.requestAuthorization()
            status = await center.authorizationStatus()
        }
        guard intent == latestIntent else { return finish(.off) }
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
