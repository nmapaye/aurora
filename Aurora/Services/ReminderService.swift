import AuroraCore
import Foundation
import UserNotifications

/// Local notifications: a daily reminder at the user's own cutoff hour, and
/// the caffeine reminders they set relative to waking. Every sync cancels
/// first and schedules again only when switched on and allowed.
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
        wakeGeneration += 1
        center.removePendingNotificationRequests(withIdentifiers: [CutoffReminder.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [CutoffReminder.identifier])
        Task { await removeWake(delivered: true) }
        defaults.removeObject(forKey: Self.wakeScheduleKey)
    }

    // MARK: Wake reminders

    enum WakeStatus: Equatable {
        case off
        case scheduled(next: Millis?)
        case denied
    }

    private let defaults = UserDefaults.standard
    private var wakeGeneration = 0
    /// Ids and fire times last handed to the system, so a reminder whose time
    /// has passed counts as delivered even after its banner is cleared.
    private static let wakeScheduleKey = "aurora.wakeReminders.scheduled"

    /// Ids of wake reminders already shown, from the system's delivered list
    /// and from earlier schedules whose time has passed.
    func deliveredWakeIDs(now: Millis) async -> Set<String> {
        let shown = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(WakeReminders.identifierPrefix) }
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
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined && prompt {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        guard current == wakeGeneration else { return .off }
        switch settings.authorizationStatus {
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
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(WakeReminders.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        if delivered {
            let shown = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(WakeReminders.identifierPrefix) }
            center.removeDeliveredNotifications(withIdentifiers: shown)
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
