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
            .tint(Palette.tint)
            .navigationTitle("Aurora Settings").navigationBarTitleDisplayMode(.inline)
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
            } message: {
                Text("Your records are kept.")
            }
        }
        .pageSizedSheet()
    }

    /// Every row is a plain row: a label, a value or control, and a chevron
    /// where it opens something. Explanations sit behind each row's info
    /// button instead of under it.
    private var connections: some View {
        Section {
            Button { showAppleHealth = true } label: {
                HStack { Label("Apple Health", systemImage: "heart.text.square"); Spacer(); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.textTertiary) }
            }
            .foregroundStyle(Palette.textPrimary)
            .accessibilityIdentifier("assistant-apple-health")
            NavigationLink { CalendarConnectionsView(service: assistant.calendars) } label: { Label("Calendars", systemImage: "calendar") }
            ExplainedRow(topic: "Intelligence", info: "\(assistant.intelligenceName). No cloud model.", infoID: "assistant-intelligence-status") {
                Label("Intelligence", systemImage: "cpu")
            }
        } header: {
            Text("Connections")
        }
        .auroraRows()
    }

    private var reminders: some View {
        Section("Caffeine Reminders") {
            NavigationLink {
                WakeRemindersView()
            } label: {
                LabeledContent("After Waking", value: wakeSummary)
            }
            .accessibilityIdentifier("assistant-wake-reminders")
            DrinkFollowUpControls()
        }
        .auroraRows()
    }

    /// The preferences store whole hours, so times are picked by the hour,
    /// in the person's locale. A row that depends on another appears only
    /// once that one is on, so no switch sits disabled.
    private var proactive: some View {
        let prefs = assistant.conversation.preferences
        return Section {
            ExplainedRow(topic: "Useful Updates", info: "Up to two a day.") {
                Toggle("Offer Useful Updates", isOn: $assistant.conversation.preferences.proactive)
            }
            if prefs.proactive {
                Toggle("Morning Briefing", isOn: $assistant.conversation.preferences.morningBriefing)
                if prefs.morningBriefing {
                    HourPicker(title: "Briefing", hour: $assistant.conversation.preferences.briefingHour, id: "assistant-briefing-hour")
                }
            }
            HourPicker(title: "Quiet Hours Begin", hour: $assistant.conversation.preferences.quietStartHour, id: "assistant-quiet-start")
            HourPicker(title: "Quiet Hours End", hour: $assistant.conversation.preferences.quietEndHour, id: "assistant-quiet-end")
            if prefs.proactive && prefs.morningBriefing {
                Button { Task { await assistant.syncBriefingNotification(prompt: true) } } label: {
                    Label("Update Briefing Notification", systemImage: "bell.badge")
                }
                .foregroundStyle(Palette.textPrimary)
            }
        } header: {
            Text("Proactive Suggestions")
        }
        .auroraRows()
    }

    #if DEBUG
    /// Development tools: compiled out of Release builds.
    private var developer: some View {
        Section("Developer") {
            #if targetEnvironment(simulator)
            Toggle("Use This Mac’s Local Ollama Model", isOn: $assistant.conversation.preferences.useMacModel)
            if assistant.conversation.preferences.useMacModel {
                TextField("Installed model name", text: $assistant.conversation.preferences.macModel)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                Text("Only your request text goes to 127.0.0.1:11434 on this Mac. Health records and calendars are not sent. This option works in the simulator only.").font(.footnote)
            }
            #endif
            NavigationLink("Design Gallery", destination: DesignGalleryView())
            // Research models side by side; Debug builds only (#89, #90).
            NavigationLink("Research Models", destination: ResearchModelsView())
                .accessibilityIdentifier("developer-research-models")
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
        }
        .auroraRows()
    }
}

/// A clock time stored as a whole hour (0–23), in the person's locale
/// (8 AM or 08:00). A navigation-link picker, so it reads like every other
/// row with a value: the title, the value and a chevron.
struct HourPicker: View {
    let title: String
    @Binding var hour: Int
    let id: String
    @Environment(AppModel.self) private var app

    var body: some View {
        Picker(title, selection: $hour) {
            ForEach(0..<24, id: \.self) { value in
                Text(app.text.clockHour(Double(value), clock: app.clock)).tag(value)
            }
        }
        .pickerStyle(.navigationLink)
        .accessibilityIdentifier(id)
    }
}
