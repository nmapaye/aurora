import AuroraCore
import SwiftUI

struct AssistantSettingsView: View {
    @Bindable var assistant: AssistantModel
    @Environment(\.dismiss) private var dismiss
    @State private var clearConversation = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Local intelligence") {
                    Text(assistant.intelligenceName)
                    Text("No cloud model, API key, or external AI service is used. Your records stay on this device.").font(.footnote)
                    #if targetEnvironment(simulator)
                    Toggle("Use this Mac’s local Ollama model", isOn: $assistant.conversation.preferences.useMacModel)
                    if assistant.conversation.preferences.useMacModel {
                        TextField("Installed model name", text: $assistant.conversation.preferences.macModel)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        Text("Only your request text goes to 127.0.0.1:11434 on this Mac. Health records and calendars are not sent. This option works in the simulator only.").font(.footnote)
                    }
                    #endif
                }
                Section("Proactive suggestions") {
                    Toggle("Offer useful updates", isOn: $assistant.conversation.preferences.proactive)
                    Toggle("Morning briefing", isOn: $assistant.conversation.preferences.morningBriefing)
                        .disabled(!assistant.conversation.preferences.proactive)
                    Stepper("Briefing: \(assistant.conversation.preferences.briefingHour):00", value: $assistant.conversation.preferences.briefingHour, in: 0...23)
                    Stepper("Quiet hours begin: \(assistant.conversation.preferences.quietStartHour):00", value: $assistant.conversation.preferences.quietStartHour, in: 0...23)
                    Stepper("Quiet hours end: \(assistant.conversation.preferences.quietEndHour):00", value: $assistant.conversation.preferences.quietEndHour, in: 0...23)
                    Text("At most two unsolicited suggestions per day, during active refreshes. Known reminders use local notifications. Aurora does not continuously reason in the background.").font(.footnote)
                    Button("Update briefing notification") { Task { await assistant.syncBriefingNotification(prompt: true) } }
                }
                #if DEBUG
                Section("Design development") {
                    NavigationLink("Design Gallery", destination: DesignGalleryView())
                }
                #endif
                Section("Connections and records") {
                    NavigationLink("Calendar connections", destination: CalendarConnectionsView(service: assistant.calendars))
                    NavigationLink("Records, exports, Health, and privacy", destination: SettingsView())
                        .accessibilityIdentifier("assistant-record-settings")
                    Button("Clear conversation", role: .destructive) { clearConversation = true }
                    Text("Clearing conversation does not delete caffeine, sleep, or reaction-test records.").font(.footnote)
                }
                if let failure = assistant.failure { Text(failure).foregroundStyle(Palette.destructive) }
            }
            .navigationTitle("Aurora settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { assistant.save(); dismiss() } } }
            .onChange(of: assistant.conversation.preferences) { _, _ in
                assistant.save()
                Task { await assistant.syncBriefingNotification(prompt: false) }
            }
            .confirmationDialog("Clear this conversation?", isPresented: $clearConversation) {
                Button("Clear conversation", role: .destructive) {
                    assistant.clearConversation()
                }
            }
        }
    }
}
