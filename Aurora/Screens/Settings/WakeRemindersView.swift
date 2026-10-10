import AuroraCore
import SwiftUI

/// Picks reminder offsets and the usual wake time. The times are the
/// person's own; nothing here suggests what they should be.
struct WakeReminderEditor: View {
    @Binding var draft: WakeReminderSettings
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 160 : 76), spacing: Metrics.xs)], spacing: Metrics.xs) {
                ForEach(WakeReminders.presetOffsets, id: \.self) { offset in
                    chip(offset)
                }
            }
            DatePicker("Usual wake time", selection: usualWake, displayedComponents: .hourAndMinute)
                .font(Typography.label)
                .frame(minHeight: Metrics.minimumTouchTarget)
                .accessibilityIdentifier("wake-usual-time")
            Text(preview)
                .font(Typography.source)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("wake-preview")
        }
    }

    private func chip(_ offset: Int) -> some View {
        let selected = draft.offsetsMinutes.contains(offset)
        let full = !selected && draft.offsetsMinutes.count >= WakeReminders.maxOffsets
        return Button {
            if selected { draft.offsetsMinutes.removeAll { $0 == offset } }
            else if !full { draft.offsetsMinutes = (draft.offsetsMinutes + [offset]).sorted() }
        } label: {
            Text("+\(WakeReminders.offsetText(offset))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
                .foregroundStyle(selected ? Palette.primaryButtonText : Palette.textPrimary)
                .background(selected ? Palette.tint : Palette.card, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Palette.tint : Palette.cardBorder))
        }
        .buttonStyle(.auroraPress)
        .disabled(full)
        .accessibilityLabel("\(WakeReminders.offsetText(offset)) after waking")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("wake-offset-\(offset)")
    }

    private var usualWake: Binding<Date> {
        Binding(
            get: {
                Date(timeIntervalSince1970: model.clock.setTime(model.now, hour: draft.usualWakeMinutes / 60, minute: draft.usualWakeMinutes % 60) / 1000)
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.usualWakeMinutes = (parts.hour ?? 8) * 60 + (parts.minute ?? 0)
            }
        )
    }

    /// The first reminder these choices would give, from real records.
    private var preview: String {
        var settings = draft
        settings.enabled = true
        guard !settings.offsetsMinutes.isEmpty else { return "Pick at least one time." }
        let plan = WakeReminders.plan(settings: settings, cutoffHour: model.state.prefs.cutoffHour, sleeps: model.state.sleeps, now: model.now, clock: model.clock, text: model.text)
        let cutoff = model.text.clockHour(model.state.prefs.cutoffHour, clock: model.clock)
        guard let next = plan.min(by: { $0.fireAt < $1.fireAt }) else { return "Nothing before your \(cutoff) cutoff." }
        let day = model.clock.dayKey(next.fireAt) == model.clock.dayKey(model.now) ? "" : "Tomorrow "
        return "Next: \(day)\(model.text.clockTime(next.fireAt)) · none after \(cutoff)"
    }
}

/// Settings: turn wake reminders on or off and change them. Changes apply
/// only on Save.
struct WakeRemindersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = WakeReminderSettings.defaults
    @State private var saving = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Toggle("Caffeine reminders after waking", isOn: $draft.enabled)
                    .accessibilityIdentifier("wake-enabled")
            }
            if draft.enabled {
                Section("When") {
                    WakeReminderEditor(draft: $draft)
                }
            }
            if case .denied = model.wakeReminderStatus {
                Section {
                    Label("Notifications are off for Aurora in Settings.", systemImage: StatusTone.warning.symbol)
                        .foregroundStyle(StatusTone.warning.foreground)
                }
            }
        }
        .navigationTitle("Wake reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saving = true
                    Task {
                        await model.saveWakeReminders(draft)
                        saving = false
                        Haptics.success()
                        dismiss()
                    }
                }
                .disabled(saving || (draft.enabled && draft.offsetsMinutes.isEmpty) || draft == (model.state.prefs.wakeReminders ?? .defaults))
                .accessibilityIdentifier("wake-save")
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = model.state.prefs.wakeReminders ?? .defaults
        }
    }
}
