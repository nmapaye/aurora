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
                Section("Connections") {
                    Button { showAppleHealth = true } label: {
                        HStack { Label("Apple Health", systemImage: "heart.text.square"); Spacer(); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.textTertiary) }
                    }
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityIdentifier("assistant-apple-health")
                    NavigationLink { CalendarConnectionsView(service: assistant.calendars) } label: { Label("Calendars", systemImage: "calendar") }
                }
                Section("Local intelligence") {
                    Text(assistant.intelligenceName)
                    Text("No cloud model. Your records stay on this device.").font(.footnote)
                    #if targetEnvironment(simulator)
                    Toggle("Use this Mac’s local Ollama model", isOn: $assistant.conversation.preferences.useMacModel)
                    if assistant.conversation.preferences.useMacModel {
                        TextField("Installed model name", text: $assistant.conversation.preferences.macModel)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        Text("Only your request text goes to 127.0.0.1:11434 on this Mac. Health records and calendars are not sent. This option works in the simulator only.").font(.footnote)
                    }
                    #endif
                }
                Section("Caffeine reminders") {
                    NavigationLink {
                        WakeRemindersView()
                    } label: {
                        LabeledContent("After waking", value: wakeSummary)
                    }
                    .accessibilityIdentifier("assistant-wake-reminders")
                }
                Section("Proactive suggestions") {
                    Toggle("Offer useful updates", isOn: $assistant.conversation.preferences.proactive)
                    Toggle("Morning briefing", isOn: $assistant.conversation.preferences.morningBriefing)
                        .disabled(!assistant.conversation.preferences.proactive)
                    Stepper("Briefing: \(assistant.conversation.preferences.briefingHour):00", value: $assistant.conversation.preferences.briefingHour, in: 0...23)
                    Stepper("Quiet hours begin: \(assistant.conversation.preferences.quietStartHour):00", value: $assistant.conversation.preferences.quietStartHour, in: 0...23)
                    Stepper("Quiet hours end: \(assistant.conversation.preferences.quietEndHour):00", value: $assistant.conversation.preferences.quietEndHour, in: 0...23)
                    Text("Up to two a day.").font(.footnote)
                    Button("Update briefing notification") { Task { await assistant.syncBriefingNotification(prompt: true) } }
                }
                #if DEBUG
                Section("Design development") {
                    NavigationLink("Design Gallery", destination: DesignGalleryView())
                }
                #endif
                Section("Records") {
                    NavigationLink("Your records, exports and privacy", destination: SettingsView(pushed: true))
                        .accessibilityIdentifier("assistant-record-settings")
                    Button("Clear conversation", role: .destructive) { clearConversation = true }
                    Text("Your records are kept.").font(.footnote)
                }
                if let failure = assistant.failure { Text(failure).foregroundStyle(Palette.destructive) }
            }
            .navigationTitle("Aurora settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { assistant.save(); dismiss() } } }
            .onChange(of: assistant.conversation.preferences) { _, _ in
                assistant.save()
                Task { await assistant.syncBriefingNotification(prompt: false) }
            }
            .sheet(isPresented: $showAppleHealth) { HealthConnectionView() }
            .confirmationDialog("Clear this conversation?", isPresented: $clearConversation) {
                Button("Clear conversation", role: .destructive) {
                    assistant.clearConversation()
                }
            }
        }
    }
}
