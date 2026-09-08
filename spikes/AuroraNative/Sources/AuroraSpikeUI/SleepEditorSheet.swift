import AuroraSpikeCore
import SwiftUI

@MainActor
struct SleepEditorSheet: View {
    let model: PreviewModel
    @State private var bedtime: Date
    @State private var wakeTime: Date
    @State private var error: String?
    private let hasSuggestion: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: PreviewModel) {
        self.model = model
        let now = Date()
        let suggestion = SleepSuggestions.nextBedtime(episodes: model.episodes, now: now, calendar: .current)
        let fallback = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 23), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
        let start = model.acceptedPlan(at: now)?.start ?? suggestion ?? fallback
        hasSuggestion = model.acceptedPlan(at: now) == nil && suggestion != nil
        _bedtime = State(initialValue: start)
        _wakeTime = State(initialValue: model.acceptedPlan(at: now)?.end ?? start.addingTimeInterval(8 * 3600))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "moon.stars.fill").font(.largeTitle).foregroundStyle(SpikeStyle.purple)
                    Text("Your next sleep window").font(.title2.bold())
                    Text(hasSuggestion ? "Suggested from the recent example nights. Accept it or choose a time that fits your day." : "Choose the time you intend to sleep. This stays a draft until you accept it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bedtime").font(.headline)
                        DatePicker("Bedtime date", selection: $bedtime, in: Date()..., displayedComponents: .date)
                            .accessibilityIdentifier("bedtime-date")
                        timePicker("Bedtime", selection: $bedtime)
                            .accessibilityIdentifier("bedtime-time")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wake time").font(.headline)
                        DatePicker("Wake date", selection: $wakeTime, in: bedtime..., displayedComponents: .date)
                        timePicker("Wake time", selection: $wakeTime)
                    }
                    Text("The preview uses this bedtime only after you accept. Caffeine estimates never move your chosen time.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }
                .padding(24)
            }
            .background(SpikeStyle.background)
            .navigationTitle("Sleep window")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button {
                    do {
                        model.plan = try SleepPlan(start: bedtime, end: wakeTime, acceptedAt: Date())
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                } label: {
                    Text("Accept sleep window").font(.headline).frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("accept-sleep-plan")
                .padding(20).background(.regularMaterial)
            }
        }
        .frame(idealWidth: 490, idealHeight: 740)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private func timePicker(_ title: String, selection: Binding<Date>) -> some View {
        #if os(iOS)
        DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        #else
        DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
            .datePickerStyle(.field)
            .controlSize(.large)
        #endif
    }
}
