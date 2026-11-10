import AuroraCore
import SwiftUI

/// Turns next-day follow-ups on yesterday's drinks on or off, and their
/// notifications. Used in the Reminders card and Aurora settings. The
/// notification switch depends on follow-ups, so it shows only once they're
/// on, nested under them.
struct DrinkFollowUpControls: View {
    @Environment(AppModel.self) private var app
    @Environment(AssistantModel.self) private var assistant

    private var settings: RepeatDrinkSettings { app.state.prefs.repeatDrinks ?? .off }

    /// A Group, not a stack: in a Form each switch is its own row, styled
    /// like every other; in the Reminders card they stack as usual. The
    /// notification switch appears once follow-ups are on, at the same
    /// indent as everything else.
    var body: some View {
        Group {
            ExplainedRow(topic: "Drink Follow-Ups", info: "After yesterday’s time passes, Aurora asks whether you had that drink, so logging it takes one tap.") {
                Toggle("Follow Up on Yesterday’s Drinks", isOn: Binding(get: { settings.enabled }, set: { enabled in
                    change(RepeatDrinkSettings(enabled: enabled, notify: enabled && settings.notify), prompt: false)
                }))
                .accessibilityIdentifier("repeat-drinks-enabled")
            }
            if settings.enabled {
                ExplainedRow(topic: "Follow-Up Notifications", info: notifyInfo, infoID: "repeat-drinks-notify-info") {
                    Toggle("Also Notify Me", isOn: Binding(get: { settings.notify }, set: { notify in
                        change(RepeatDrinkSettings(enabled: settings.enabled, notify: notify), prompt: notify)
                    }))
                    .accessibilityIdentifier("repeat-drinks-notify")
                }
                // A status that needs action stays visible.
                if settings.notify, assistant.repeatDrinkStatus == .denied {
                    NotificationsOffNotice(detail: "Follow-ups still appear here.")
                } else if settings.notify, let note = notifyNote {
                    Text(note)
                        .font(.footnote).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("repeat-drinks-notify-note")
                }
            }
        }
    }

    private var notifyInfo: String { "One silent notification a day, without amounts." }

    /// Why notifications aren't arriving although they're on: paused after
    /// unanswered days, or the briefing uses Aurora's one notification a day.
    private var notifyNote: String? {
        if assistant.repeatDrinksPaused { return "Paused after several unanswered days. Turn off and on to resume." }
        if !NotificationBudget.followUpsMayNotify(assistant.conversation.preferences) {
            return "The morning briefing uses Aurora’s one notification a day. Follow-ups appear here."
        }
        return nil
    }

    private func change(_ new: RepeatDrinkSettings, prompt: Bool) {
        // Turning notifications on again resumes them after a pause.
        if new.notify && !settings.notify { assistant.resumeRepeatDrinkNotifications() }
        guard app.setRepeatDrinks(new) else { return }
        assistant.deliverRepeatDrinks(app: app)
        Task { await assistant.syncRepeatDrinkNotifications(app: app, prompt: prompt) }
    }
}
