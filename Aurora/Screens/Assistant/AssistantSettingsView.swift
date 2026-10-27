import AuroraCore
import SwiftUI

struct AssistantSettingsView: View {
    @Bindable var assistant: AssistantModel
    @Environment(\.dismiss) private var dismiss
    @State private var clearConversation = false
    @State private var showAppleHealth = false
    @Environment(AppModel.self) private var app
    private var wakeSummary: String {
        guard let settings = app.state.prefs.wakeReminders?.normalized(), settings.enabled, !settings.offsetsMinutes.isEmpty else { return "Off" }
        return settings.offsetsMinutes.map { "+" + WakeReminders.offsetText($0) }.joined(separator: ", ")
    }
    var body: some View {
        NavigationStack {
            Form {
                connections
                reminders
                proactive
                #if DEBUG
                developer
                #endif
                records
                if let failure = assistant.failure { Text(failure).foregroundStyle(Palette.destructive).auroraRows() }
            }
            .auroraGroupedList()
            .navigationTitle("Aurora settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { assistant.save(); dismiss() }.keyboardShortcut(.cancelAction) } }
            .onChange(of: assistant.conversation.preferences) { _, _ in
                assistant.save()
                // The briefing decides whether follow-ups may notify, and
                // quiet hours shape follow-ups and usual-wake reminders.
                Task {
                    await assistant.syncBriefingNotification(prompt: false)
                    await assistant.syncRepeatDrinkNotifications(app: app)
                    await app.syncWakeReminders()
                }
            }
            .sheet(isPresented: $showAppleHealth) { HealthConnectionView() }
            .confirmationDialog("Clear this conversation?", isPresented: $clearConversation) {
                Button("Clear conversation", role: .destructive) { assistant.requestClear() }
            }
        }
        .pageSizedSheet()
    }

    /// The intelligence in use is a status, not a setting, so it is the
    /// footer here rather than a row that looks like a heading.
    private var connections: some View {
        Section {
            Button { showAppleHealth = true } label: {
                HStack { Label("Apple Health", systemImage: "heart.text.square"); Spacer(); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.textTertiary) }
            }
            .foregroundStyle(Palette.textPrimary)
            .accessibilityIdentifier("assistant-apple-health")
            NavigationLink { CalendarConnectionsView(service: assistant.calendars) } label: { Label("Calendars", systemImage: "calendar") }
        } header: {
            Text("Connections")
        } footer: {
            Text("\(assistant.intelligenceName). No cloud model.")
                .accessibilityIdentifier("assistant-intelligence-status")
        }
        .auroraRows()
    }

    private var reminders: some View {
        Section("Caffeine reminders") {
            NavigationLink {
                WakeRemindersView()
            } label: {
                LabeledContent("After waking", value: wakeSummary)
            }
            .accessibilityIdentifier("assistant-wake-reminders")
            DrinkFollowUpControls()
        }
        .auroraRows()
    }

    /// Clock times use the system time picker in the person's locale. The
    /// preferences store whole hours, so a picked time keeps its hour and
    /// minutes return to :00.
    private var proactive: some View {
        Section {
            Toggle("Offer useful updates", isOn: $assistant.conversation.preferences.proactive)
            Toggle("Morning briefing", isOn: $assistant.conversation.preferences.morningBriefing)
                .disabled(!assistant.conversation.preferences.proactive)
            HourPicker(title: "Briefing", hour: $assistant.conversation.preferences.briefingHour, id: "assistant-briefing-hour")
            HourPicker(title: "Quiet hours begin", hour: $assistant.conversation.preferences.quietStartHour, id: "assistant-quiet-start")
            HourPicker(title: "Quiet hours end", hour: $assistant.conversation.preferences.quietEndHour, id: "assistant-quiet-end")
            Button("Update briefing notification") { Task { await assistant.syncBriefingNotification(prompt: true) } }
        } header: {
            Text("Proactive suggestions")
        } footer: {
            Text("Up to two a day. Times are on the hour.")
        }
        .auroraRows()
    }

    #if DEBUG
    /// Development tools: compiled out of Release builds.
    private var developer: some View {
        Section("Developer") {
            #if targetEnvironment(simulator)
            Toggle("Use this Mac’s local Ollama model", isOn: $assistant.conversation.preferences.useMacModel)
            if assistant.conversation.preferences.useMacModel {
                TextField("Installed model name", text: $assistant.conversation.preferences.macModel)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                Text("Only your request text goes to 127.0.0.1:11434 on this Mac. Health records and calendars are not sent. This option works in the simulator only.").font(.footnote)
            }
            #endif
            NavigationLink("Design Gallery", destination: DesignGalleryView())
        }
        .auroraRows()
    }
    #endif

    private var records: some View {
        Section {
            NavigationLink(SettingsView.recordsTitle, destination: SettingsView(pushed: true))
                .accessibilityIdentifier("assistant-record-settings")
            Button("Clear conversation", role: .destructive) { clearConversation = true }
        } header: {
            Text("Records")
        } footer: {
            Text("Clearing the conversation keeps your records.")
        }
        .auroraRows()
    }
}

/// A clock time stored as a whole hour (0–23), picked with the compact
/// system time picker so it reads in the person's locale (8:00 AM or 08:00).
struct HourPicker: View {
    let title: String
    @Binding var hour: Int
    let id: String
    @Environment(AppModel.self) private var app

    var body: some View {
        DatePicker(title, selection: time, displayedComponents: .hourAndMinute)
            .accessibilityIdentifier(id)
    }

    private var time: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: app.clock.setTime(app.now, hour: hour, minute: 0) / 1000) },
            set: { date in
                // A minutes-only change keeps the stored hour untouched.
                let picked = Calendar.current.component(.hour, from: date)
                if picked != hour { hour = picked }
            }
        )
    }
}
