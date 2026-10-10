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
    }

    private let center = UNUserNotificationCenter.current()
    private var generation = 0

    func cancelForErase() {
        generation += 1
        let ids = [CutoffReminder.identifier, CutoffScenario.reminderIdentifier]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    enum ScenarioOutcome: Equatable { case scheduled, notAllowed, failed }

    /// One reminder at a cutoff scenario's instant, apart from the daily
    /// cutoff reminder, which it never changes. Never asks for permission.
    /// A fixed identifier means a repeated Save replaces, never duplicates.
    func scheduleScenario(_ content: CutoffScenario.ReminderContent) async -> ScenarioOutcome {
        let currentGeneration = generation
        let settings = await center.notificationSettings()
        guard generation == currentGeneration else { return .failed }
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return .notAllowed }
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
            guard generation == currentGeneration else {
                center.removePendingNotificationRequests(withIdentifiers: [CutoffScenario.reminderIdentifier])
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
        center.removePendingNotificationRequests(withIdentifiers: [CutoffReminder.identifier])
        guard enabled else { return .off }

        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined && prompt {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        guard generation == currentGeneration else { return .off }
        switch settings.authorizationStatus {
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
                center.removePendingNotificationRequests(withIdentifiers: [CutoffReminder.identifier])
                return .off
            }
            return .scheduled(hour: content.hour)
        } catch {
            return .denied
        }
    }
}
