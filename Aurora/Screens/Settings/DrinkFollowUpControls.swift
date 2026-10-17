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

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Toggle(isOn: Binding(get: { settings.enabled }, set: { enabled in
                change(RepeatDrinkSettings(enabled: enabled, notify: enabled && settings.notify), prompt: false)
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Follow up on yesterday’s drinks")
                    Text("At the time you had one, Aurora asks whether you had it again, so logging it takes one tap.")
                        .font(.footnote).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("repeat-drinks-enabled")
            if settings.enabled {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Toggle("Also notify me", isOn: Binding(get: { settings.notify }, set: { notify in
                        change(RepeatDrinkSettings(enabled: settings.enabled, notify: notify), prompt: notify)
                    }))
                    .accessibilityIdentifier("repeat-drinks-notify")
                    if settings.notify, assistant.repeatDrinkStatus == .denied {
                        NotificationsOffNotice(detail: "Follow-ups still appear here.")
                    }
                }
                .padding(.leading, Metrics.md)
            } else {
                Text("Notifications are available once this is on.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func change(_ new: RepeatDrinkSettings, prompt: Bool) {
        guard app.setRepeatDrinks(new) else { return }
        assistant.deliverRepeatDrinks(app: app)
        Task { await assistant.syncRepeatDrinkNotifications(app: app, prompt: prompt) }
    }
}
