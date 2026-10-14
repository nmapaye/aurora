import AuroraCore
import SwiftUI

/// Sleep: recorded nights first, then the most recent night with its date
/// and source, caffeine timing once 14 paired nights exist, and the Sleep
/// Data controls. Nothing here suggests a bedtime or a dose.
struct SleepView: View {
    /// Pushed inside Your records: keeps the system bar (see `AppScreen`).
    var pushed = false
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var range: SleepRange = .week
    /// Every entry opens in this screen's own stack, so a sheet stays put.
    @State private var showHistory = false
    @State private var showDistribution = false
    @State private var showSources = false
    @State private var editing: SleepSheet?
    @State private var loading = false
    @State private var savedCount = 0

    var body: some View {
        let state = model.state
        let presentation = SleepModel.presentation(
            sessions: state.sleeps, targetSleepHours: state.prefs.targetSleep, range: range,
            now: model.now, clock: model.clock, text: model.text
        )
        AppScreen(title: "Sleep", pushed: pushed) {
            Button("Add Data") { editing = .new }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("sleep-add-data")
        } content: {
            RangeControl(
                label: "Sleep range",
                options: [(SleepRange.week, "W", "Week"), (.month, "M", "Month")],
                selection: $range
            )
            WideColumns {
                chart(presentation, target: state.prefs.targetSleep)
            } trailing: {
                recentNight(state)
                caffeineTiming(state)
            }
            sleepData(state)
        }
        .refreshable {
            guard state.healthChoices.readSleep, !state.demoMode else { return }
            await model.importHealth()
        }
        .sensoryFeedback(.success, trigger: savedCount)
        .navigationDestination(isPresented: $showHistory) { SleepHistoryView() }
        .sheet(item: $editing) { sheet in
            SleepEntrySheet(mode: sheet) { draft in
                switch sheet {
                case .new: model.addManualSleep(draft)
                case .edit(let session): model.correctManualSleep(id: session.id, with: draft)
                }
                savedCount += 1
                UIAccessibility.post(notification: .announcement, argument: "Sleep session saved.")
            } onDelete: {
                if case .edit(let session) = sheet { model.deleteManualSleep(id: session.id) }
            }
        }
    }

    private func chart(_ presentation: SleepPresentation, target: Double) -> some View {
        let days = presentation.points.map { point -> DailyBarChart.Day in
            let readout = SleepModel.describeChartDay(point, text: model.text)
            return DailyBarChart.Day(
                date: point.date,
                value: point.durationMs.map { $0 / hourMs },
                title: readout.title,
                readout: readout.value
            )
        }
        return DailyBarChart(
            title: "Time Asleep",
            days: days,
            unit: "Hours",
            accent: Palette.sleepAccent,
            reference: (target, "\(OnboardingCopy.formatSleepTarget(target).value)h target"),
            defaultIndex: days.lastIndex { $0.value != nil },
            accessibilitySummary: presentation.accessibilitySummary,
            emptyMessage: "No sleep recorded in this range. Add a night or connect Apple Health in Sleep Data."
        )
    }

    private func recentNight(_ state: AppState) -> some View {
        let signal = SleepModel.recentNightSignal(
            sleeps: state.sleeps, targetSleepHours: state.prefs.targetSleep, now: model.now, clock: model.clock, text: model.text
        )
        return SignalCard(model: signal, symbol: "bed.double.fill", accent: Palette.sleepAccent) {
            if signal.status == .empty {
                editing = .new
            } else {
                showHistory = true
            }
        }
    }

    @ViewBuilder
    private func caffeineTiming(_ state: AppState) -> some View {
        let timing = SleepModel.caffeineTimingSignal(sleeps: state.sleeps, doses: state.doses, now: model.now, clock: model.clock)
        Card {
            Text(SleepModel.caffeineTimingLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            switch timing {
            case .gathering(let paired, let required, let text):
                ProgressView(value: Double(paired), total: Double(required))
                    .tint(Palette.caffeineAccent)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .observed(_, let period, let value, let context, let rows, let label):
                Text(value)
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityLabel(label)
                Text(period).font(.footnote.weight(.medium)).foregroundStyle(Palette.textSecondary)
                Text(context).font(.footnote).foregroundStyle(Palette.textSecondary)
                Button(showDistribution ? "Hide Distribution" : "Show Distribution") {
                    showDistribution.toggle()
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel("Timing distribution")
                .accessibilityHint(showDistribution ? "Hides the timing distribution" : "Shows the timing distribution")
                if showDistribution {
                    ForEach(rows, id: \.title) { row in
                        HStack {
                            Text(row.title).foregroundStyle(Palette.textSecondary)
                            Spacer()
                            Text(row.value).foregroundStyle(Palette.textPrimary)
                        }
                        .font(.footnote)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func sleepData(_ state: AppState) -> some View {
        let status = SleepDataStatus.describe(
            onboarding: state.onboarding, healthSync: state.healthSync, demoMode: state.demoMode, healthAvailable: model.healthAvailable
        )
        let sync = state.healthSync
        return VStack(alignment: .leading, spacing: Metrics.sm) {
            Button {
                withAnimation(Motion.stateChange(reduceMotion: reduceMotion)) { showSources.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sleep Data").font(.headline).foregroundStyle(Palette.textPrimary)
                        Text(status.state).font(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    Image(systemName: showSources ? "chevron.up" : "chevron.down").foregroundStyle(Palette.textTertiary)
                }
                .padding(Metrics.md)
                .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
                .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.cardBorder))
            }
            .buttonStyle(.auroraPress)
            .accessibilityLabel("Sleep Data, \(status.state)")
            .accessibilityHint(showSources ? "Hides Health, manual, and sample data controls" : "Shows Health, manual, and sample data controls")
            .accessibilityIdentifier("sleep-data")

            if showSources {
                Card {
                    Text(status.state).font(.headline).foregroundStyle(Palette.textPrimary)
                    Text(status.detail).font(.subheadline).foregroundStyle(Palette.textSecondary)
                    Text("\(sync.importedCount) \(sync.importedCount == 1 ? "night" : "nights") from Apple Health · read-only\(sync.lastSyncedAt.map { " · synced \(model.text.clockTime($0))" } ?? "")")
                        .font(.footnote).foregroundStyle(Palette.textSecondary)
                    if let message = sync.lastMessage {
                        Text(message).font(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                    Button {
                        Task {
                            loading = true
                            await model.connectHealth()
                            loading = false
                        }
                    } label: {
                        if loading { ProgressView() } else { Text(state.onboarding.permissionStatus == .granted ? "Refresh from Apple Health" : "Connect Apple Health") }
                    }
                    .buttonStyle(.auroraPrimary)
                    .disabled(loading || !model.healthAvailable)
                    // One tidy list instead of mismatched side-by-side buttons.
                    VStack(spacing: 0) {
                        dataRow("Add sleep manually", symbol: "plus.circle") { editing = .new }
                        Divider()
                        dataRow("All sleep entries", symbol: "list.bullet", value: "\(state.sleeps.count)") { showHistory = true }
                        Divider()
                        dataRow(state.demoMode ? "Refresh Sample Data" : "Load Sample Data", symbol: "sparkles") { model.loadSampleData() }
                        if state.demoMode {
                            Divider()
                            dataRow("Clear Sample Data", symbol: "trash", destructive: true) { model.clearSampleData() }
                        }
                    }
                    .background(Palette.cardMuted, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
                }
                .accessibilityIdentifier("sleep-data-panel")
            }
        }
    }
}

extension SleepView {
    /// A full-width row: icon, title, optional value, chevron.
    func dataRow(_ title: String, symbol: String, value: String? = nil, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Metrics.sm) {
                Image(systemName: symbol).frame(width: 24).foregroundStyle(destructive ? Palette.destructive : Palette.tint)
                Text(title).foregroundStyle(destructive ? Palette.destructive : Palette.textPrimary)
                Spacer(minLength: Metrics.xs)
                if let value { Text(value).monospacedDigit().foregroundStyle(Palette.textSecondary) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.textTertiary)
            }
            .font(Typography.evidence)
            .padding(.horizontal, Metrics.md)
            .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget + 4)
        }
        .buttonStyle(.auroraPress)
    }
}

enum SleepSheet: Identifiable {
    case new
    case edit(SleepSession)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let session): session.id
        }
    }
}

/// Add Sleep and Edit Sleep for manual entries: local start and end times
/// and a note. Delete asks first.
struct SleepEntrySheet: View {
    let mode: SleepSheet
    let onSave: (ManualSleep.Draft) -> Void
    let onDelete: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft = ManualSleep.Draft(start: 0, end: 0, note: "")
    @State var loaded = false
    @State var confirmDelete = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        let validation = ManualSleep.validate(start: draft.start, end: draft.end, now: AppModel.currentMillis())
        NavigationStack {
            Form {
                Section {
                    Text("Choose the local start and end time for this sleep session.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                    DatePicker("Start", selection: binding(\.start), in: ...Date.now)
                    DatePicker("End", selection: binding(\.end), in: ...Date.now)
                    TextField("Optional note", text: $draft.note, axis: .vertical)
                        .accessibilityLabel("Sleep note")
                }
                if let message = validation.message {
                    Section {
                        Text(message).foregroundStyle(StatusTone.error.foreground)
                    }
                }
                if isEditing {
                    Section {
                        Button("Delete Sleep", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.modalBackground)
            .navigationTitle(isEditing ? "Edit Sleep" : "Add Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(validation != .valid)
                }
            }
            .alert("Delete this sleep session?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    Haptics.warning()
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            switch mode {
            case .new: draft = AssistantPlanner.usualNight(model.state.sleeps, now: AppModel.currentMillis(), clock: model.clock) ?? ManualSleep.newDraft(now: AppModel.currentMillis())
            case .edit(let session): draft = ManualSleep.Draft(start: session.start, end: session.end, note: session.note ?? "")
            }
        }
    }

    private func binding(_ key: WritableKeyPath<ManualSleep.Draft, Millis>) -> Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: draft[keyPath: key] / 1000) },
            set: { draft[keyPath: key] = ($0.timeIntervalSince1970 * 1000).rounded() }
        )
    }
}

/// Every sleep session, newest first, with its source. Only manual sessions
/// can be edited or deleted.
struct SleepHistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: SleepSheet?

    var body: some View {
        let sessions = model.state.sleeps.sorted { $0.end > $1.end }
        List {
            if sessions.isEmpty {
                Text("No sleep recorded yet.").foregroundStyle(Palette.textSecondary)
            }
            ForEach(sessions) { session in
                row(session)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.screen)
        .navigationTitle("Sleep History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { sheet in
            SleepEntrySheet(mode: sheet) { draft in
                if case .edit(let session) = sheet { model.correctManualSleep(id: session.id, with: draft) }
            } onDelete: {
                if case .edit(let session) = sheet { model.deleteManualSleep(id: session.id) }
            }
        }
    }

    private func row(_ session: SleepSession) -> some View {
        let manual = RecordID.isManualSleep(session.id)
        let source = SleepModel.sourceLabel(id: session.id)
        let span = "\(model.text.weekdayDate(session.end)) · \(model.text.clockTime(session.start)) – \(model.text.clockTime(session.end))"
        let content = HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatHoursMinutes(durationMs: session.end - session.start) + (session.type == .nap ? " nap" : ""))
                    .font(.headline)
                    .foregroundStyle(source == "Sample Data" ? Palette.textSecondary : Palette.textPrimary)
                Text(span).font(.footnote).foregroundStyle(Palette.textSecondary)
                if let note = session.note, !note.isEmpty {
                    Text(note).font(.footnote).foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            Text(source)
                .font(.caption.weight(.semibold))
                .foregroundStyle(source == "Sample Data" ? StatusTone.warning.foreground : Palette.textSecondary)
        }
        .contentShape(Rectangle())
        return Group {
            if manual {
                Button { editing = .edit(session) } label: { content }
                    .buttonStyle(.auroraPress)
                    .swipeActions {
                        Button("Delete", role: .destructive) { model.deleteManualSleep(id: session.id) }
                        Button("Edit") { editing = .edit(session) }.tint(Palette.tint)
                    }
                    .accessibilityHint("Edit or delete this manual sleep")
            } else {
                content
            }
        }
        .listRowBackground(source == "Sample Data" ? Palette.cardMuted : Palette.card)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(formatHoursMinutes(durationMs: session.end - session.start)), \(span), \(source)\(manual ? "" : ", read-only")")
    }
}
