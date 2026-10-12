import AuroraCore
import Foundation
import UserNotifications

/// The daily reminder at the user's own cutoff hour, plus at most one
/// one-off cutoff scenario reminder the person saved. Every sync cancels the
/// daily one first and schedules it again only when it is switched on and allowed.
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
    private var generation = 0

    init(backend: (any NotificationBackend)? = nil) {
        center = backend ?? LiveNotificationBackend()
    }

    func cancelForErase() {
        generation += 1
        let ids = [CutoffReminder.identifier, CutoffScenario.reminderIdentifier]
        center.removePending(ids)
        center.removeDelivered(ids)
    }

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

    /// `prompt` asks for permission when it hasn't been decided yet. Only
    /// Settings passes `true`; foreground syncs never prompt.
    func sync(enabled: Bool, cutoffHour: Double, prompt: Bool) async -> Status {
        let currentGeneration = generation
        center.removePending([CutoffReminder.identifier])
        guard enabled else { return .off }

        var status = await center.authorizationStatus()
        if status == .notDetermined && prompt {
            await center.requestAuthorization()
            status = await center.authorizationStatus()
        }
        guard generation == currentGeneration else { return .off }
        switch status {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return .denied
        }

        let content = CutoffReminder.content(cutoffHour: cutoffHour, clock: .current, text: .current)
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
            guard generation == currentGeneration else {
                center.removePending([CutoffReminder.identifier])
                return .off
            }
            return .scheduled(hour: content.hour)
        } catch {
            return .failed
        }
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
}

/// Every call goes through one serial queue off the main thread. Removal is
/// a synchronous XPC round trip that blocked the main thread for minutes on
/// a freshly booted simulator (spindump: `foregroundSync → sync →
/// removePendingNotificationRequests → xpc_connection_send_message_with_reply_sync`).
/// One queue keeps calls in the order Aurora made them, so a removal
/// requested before an add can never land after it.
final class LiveNotificationBackend: NotificationBackend {
    private let center = UNUserNotificationCenter.current()
    private let queue = DispatchQueue(label: "com.nmapaye.aurora.notifications", qos: .userInitiated)

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
}
