import AuroraCore
import Foundation
import UserNotifications

/// The one local notification: a daily reminder at the user's own cutoff
/// hour. Every sync cancels it first and schedules it again only when it is
/// switched on and allowed.
final class ReminderService: @unchecked Sendable {
    enum Status: Equatable {
        case off
        case scheduled(hour: Int)
        case denied
    }

    private let center = UNUserNotificationCenter.current()

    /// `prompt` asks for permission when it hasn't been decided yet. Only
    /// Settings passes `true`; foreground syncs never prompt.
    func sync(enabled: Bool, cutoffHour: Double, prompt: Bool) async -> Status {
        center.removePendingNotificationRequests(withIdentifiers: [CutoffReminder.identifier])
        guard enabled else { return .off }

        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined && prompt {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
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
            return .scheduled(hour: content.hour)
        } catch {
            return .denied
        }
    }
}
