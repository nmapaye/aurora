import AuroraCore
import SwiftUI

/// A cutoff scenario inside its card: the open inputs while the card can
/// act, then the frozen result with its capture time, zone and assumptions.
/// Editing never records a dose or writes a notification; a reminder is
/// scheduled only by Save on a current preview.
struct CutoffScenarioCardView: View {
    let message: ConversationMessage
    let card: AssistantCard
    let active: Bool
    @Environment(AppModel.self) private var app
    @Environment(AssistantModel.self) private var assistant
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var field: Field?

    private enum Field: Hashable { case threshold, amount }
    private typealias S = CutoffScenario

    private var zone: TimeZone { TimeZone(identifier: card.timeZone) ?? .current }
    private var text: DateText { .localized(timeZone: zone) }
    private var input: S.Input? { active ? assistant.pendingCutoff : nil }
    private var snapshot: S.Snapshot? { card.cutoff }
    private var inputsChanged: Bool { input != nil && input != snapshot?.input }
    private var preview: CutoffReminderPreview? { assistant.cutoffPreview.flatMap { $0.messageID == message.id ? $0 : nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.md) {
            if let input {
                editor(input)
                    .transition(Motion.stateTransition(reduceMotion: reduceMotion))
            }
            if let snapshot { result(snapshot) }
            if active { reminder }
            if !active {
                Text(card.state == .expired ? "This scenario expired. Refresh for a new snapshot with the same inputs." : "This scenario is closed. Refresh for a new snapshot with the same inputs.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            }
        }
        // Decimal pads have no return key; Done ends editing so Calculate is reachable.
        .toolbar {
            if field != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { field = nil }.accessibilityIdentifier("cutoff-keyboard-done")
                }
            }
        }
        .onChange(of: field) { _, value in assistant.cardFocus(message.id, focused: value != nil) }
        .onDisappear { assistant.cardFocus(message.id, focused: false) }
    }

    // MARK: Editor

    @ViewBuilder private func editor(_ input: S.Input) -> some View {
        let problems = live(input).result.problems
        VStack(alignment: .leading, spacing: Metrics.md) {
            SectionLabel(text: "Your scenario")
            Text("Times in \(zone.identifier)").font(Typography.source).foregroundStyle(Palette.textSecondary)
            localTime("Bedtime", key: \.bedtime, occurrence: \.bedtimeOccurrence, id: "bedtime", add: "Add bedtime", optional: false)
                .disabled(assistant.savingCutoffReminder)
            problemLabels(problems, [.bedtimeRepeated, .bedtimeSkipped, .bedtimeInvalid, .bedtimeNotAfterCapture])
            LabeledField(label: "Threshold at bedtime", unit: "mg") {
                TextField("Enter mg", text: binding(\.thresholdMg))
                    .keyboardType(.decimalPad).font(Typography.evidence).monospacedDigit()
                    .focused($field, equals: .threshold).accessibilityLabel("Threshold at bedtime, milligrams")
                    .accessibilityIdentifier("cutoff-threshold")
            }
            .disabled(assistant.savingCutoffReminder)
            if !input.thresholdMg.isEmpty { problemLabels(problems, [.invalidThreshold]) }
            assumptionRow
            LabeledField(label: "Hypothetical drink · optional", unit: "mg") {
                TextField("Enter mg", text: binding(\.drinkMg))
                    .keyboardType(.decimalPad).font(Typography.evidence).monospacedDigit()
                    .focused($field, equals: .amount).accessibilityLabel("Hypothetical drink, milligrams, optional")
                    .accessibilityIdentifier("cutoff-amount")
            }
            .disabled(assistant.savingCutoffReminder)
            problemLabels(problems, [.invalidAmount])
            localTime("Hypothetical drink time", key: \.drinkTime, occurrence: \.drinkOccurrence, id: "drink", add: "Add drink time", optional: true)
                .disabled(assistant.savingCutoffReminder)
            problemLabels(problems, [.drinkTimeRepeated, .drinkTimeSkipped, .drinkTimeInvalid, .drinkTimeBeforeCapture, .drinkTimeAfterBedtime])
            Text("Nothing here is recorded. Log caffeine records a drink you had.")
                .font(Typography.source).foregroundStyle(Palette.textSecondary)
            VStack(spacing: Metrics.xxs) {
                // One primary action: Save leads while a reminder preview is open.
                if preview == nil {
                    Button("Calculate") { field = nil; assistant.calculateCutoff(app: app) }
                        .buttonStyle(.auroraPrimary).accessibilityIdentifier("cutoff-calculate")
                } else {
                    Button("Calculate") { field = nil; assistant.calculateCutoff(app: app) }
                        .buttonStyle(.auroraSecondary).accessibilityIdentifier("cutoff-calculate")
                }
                Button("Close") { field = nil; assistant.discardDraft() }
                    .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
                    .accessibilityIdentifier("cutoff-close")
            }
            .padding(.top, Metrics.xxs)
        }
    }

    /// Inline problems mirror Calculate's own check against the current
    /// records; they never replace it.
    private func live(_ input: S.Input) -> S.Snapshot {
        S.evaluate(input: input, doses: [], halfLifeHours: app.state.prefs.halfLife, now: AppModel.currentMillis(), timeZone: zone)
    }

    @ViewBuilder private func problemLabels(_ problems: [S.Problem], _ shown: [S.Problem]) -> some View {
        ForEach(problems.filter { shown.contains($0) }, id: \.self) { problem in
            Label(problem.message(timeZone: zone.identifier), systemImage: (problem.isMissing ? StatusTone.warning : StatusTone.error).symbol)
                .font(.footnote).foregroundStyle(problem.isMissing ? Palette.textSecondary : Palette.destructive)
        }
    }

    private var assumptionRow: some View {
        let halfLife = app.state.prefs.halfLife
        let problem = S.halfLifeProblem(halfLife)
        return VStack(alignment: .leading, spacing: Metrics.xxs) {
            valueRow("Half-life", problem == nil ? "\(numberText(halfLife)) h" : "Can’t be used", spoken: problem == nil ? "\(numberText(halfLife)) hours" : "can’t be used")
            Text(S.assumption).font(Typography.source).foregroundStyle(Palette.textSecondary)
            if let problem {
                // The setting itself is wrong; there's nothing to enter on this card.
                Label(problem, systemImage: StatusTone.error.symbol)
                    .font(.footnote).foregroundStyle(Palette.destructive)
                    .accessibilityIdentifier("cutoff-halflife-problem")
                Button("Open Settings") { assistant.historySheet = .settings }
                    .font(.subheadline.weight(.medium)).frame(minHeight: Metrics.minimumTouchTarget)
            }
        }
    }

    private func binding(_ key: WritableKeyPath<S.Input, String>) -> Binding<String> {
        Binding(get: { assistant.pendingCutoff?[keyPath: key] ?? "" }, set: { value in assistant.editCutoff { $0[keyPath: key] = value } })
    }

    /// Date and time as separate native pickers, so a wall time that clocks
    /// skip or repeat can be chosen and is then resolved explicitly.
    @ViewBuilder private func localTime(_ label: String, key: WritableKeyPath<S.Input, S.LocalTime?>, occurrence: WritableKeyPath<S.Input, S.Occurrence?>, id: String, add: String, optional: Bool) -> some View {
        if let value = assistant.pendingCutoff?[keyPath: key] {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(label).font(Typography.label).foregroundStyle(Palette.textSecondary)
                pickerRow("Date") {
                    DatePicker("\(label) date", selection: dayBinding(key), displayedComponents: .date)
                        .labelsHidden().accessibilityLabel("\(label) date").accessibilityIdentifier("cutoff-\(id)-date")
                }
                pickerRow("Time") {
                    DatePicker("\(label) time", selection: timeBinding(key), displayedComponents: .hourAndMinute)
                        .labelsHidden().accessibilityLabel("\(label) time").accessibilityIdentifier("cutoff-\(id)-time")
                }
                if case .repeated(let first, let second) = S.resolve(value, in: zone) {
                    Picker("Which \(text.clockTime(first))?", selection: Binding(
                        get: { assistant.pendingCutoff?[keyPath: occurrence] },
                        set: { choice in assistant.editCutoff { $0[keyPath: occurrence] = choice } }
                    )) {
                        Text("First · \(zone.abbreviation(for: date(first)) ?? "")").tag(Optional(S.Occurrence.first))
                        Text("Second · \(zone.abbreviation(for: date(second)) ?? "")").tag(Optional(S.Occurrence.second))
                    }
                    .pickerStyle(.segmented).frame(minHeight: Metrics.minimumTouchTarget)
                    .accessibilityIdentifier("cutoff-\(id)-occurrence")
                }
                if optional {
                    Button("Remove drink time") { assistant.editCutoff { $0[keyPath: key] = nil; $0[keyPath: occurrence] = nil } }
                        .font(.subheadline).frame(minHeight: Metrics.minimumTouchTarget)
                }
            }
        } else {
            // Starts at the current local time: a neutral starting point to
            // edit, never a proposed bedtime or drink time.
            Button(add) { assistant.editCutoff { $0[keyPath: key] = S.LocalTime(AppModel.currentMillis(), timeZone: zone) } }
                .buttonStyle(.auroraSecondary).accessibilityIdentifier("cutoff-add-\(id)")
        }
    }

    /// A short label beside its picker, stacked above it when large text no
    /// longer fits both; the section label above already names the field.
    private func pickerRow<Control: View>(_ title: String, @ViewBuilder picker: () -> Control) -> some View {
        let picker = picker()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.sm) {
                Text(title).font(Typography.evidence)
                Spacer(minLength: 0)
                picker
            }
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(title).font(Typography.evidence)
                picker
            }
        }
        .frame(minHeight: Metrics.minimumTouchTarget)
    }

    private func date(_ ms: Millis) -> Date { Date(timeIntervalSince1970: ms / 1000) }

    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = zone; return c }

    private func dayBinding(_ key: WritableKeyPath<S.Input, S.LocalTime?>) -> Binding<Date> {
        Binding(get: {
            let v = assistant.pendingCutoff?[keyPath: key]
            // Noon always exists, whatever the zone does that day.
            return calendar.date(from: DateComponents(year: v?.year, month: v?.month, day: v?.day, hour: 12)) ?? .now
        }, set: { picked in
            let parts = calendar.dateComponents([.year, .month, .day], from: picked)
            assistant.editCutoff {
                $0[keyPath: key]?.year = parts.year ?? 1970; $0[keyPath: key]?.month = parts.month ?? 1; $0[keyPath: key]?.day = parts.day ?? 1
                clearOccurrence(&$0, key)
            }
        })
    }

    private func timeBinding(_ key: WritableKeyPath<S.Input, S.LocalTime?>) -> Binding<Date> {
        Binding(get: {
            let v = assistant.pendingCutoff?[keyPath: key]
            // A reference day with no clock change, so every wall time is selectable.
            return calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: v?.hour, minute: v?.minute)) ?? .now
        }, set: { picked in
            let parts = calendar.dateComponents([.hour, .minute], from: picked)
            assistant.editCutoff {
                $0[keyPath: key]?.hour = parts.hour ?? 0; $0[keyPath: key]?.minute = parts.minute ?? 0
                clearOccurrence(&$0, key)
            }
        })
    }

    /// A different wall time needs its own choice of occurrence.
    private func clearOccurrence(_ input: inout S.Input, _ key: WritableKeyPath<S.Input, S.LocalTime?>) {
        if key == \S.Input.bedtime { input.bedtimeOccurrence = nil } else { input.drinkOccurrence = nil }
    }

    // MARK: Result

    @ViewBuilder private func result(_ snapshot: S.Snapshot) -> some View {
        let r = snapshot.result
        VStack(alignment: .leading, spacing: Metrics.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { SectionLabel(text: "Result"); Spacer(minLength: 0); resultBadge }
                VStack(alignment: .leading, spacing: Metrics.xxs) { SectionLabel(text: "Result"); resultBadge }
            }
            if inputsChanged {
                Label("Inputs changed. Calculate to update this result.", systemImage: StatusTone.info.symbol)
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            if let bedtime = r.bedtime {
                metric("Bedtime", text.fullDateTime(bedtime), source: zoneLabel(bedtime))
            }
            if let existing = r.existing {
                metric("Modeled caffeine at bedtime · existing records", mg(existing.totalMg), source: provenance(existing))
                if existing.includesSample {
                    StatusBadge(text: "Includes Sample Data · \(mg(existing.sampleMg))", tone: .info)
                }
            }
            if r.amountMg != nil {
                if let hypothetical = r.hypotheticalMg, let drinkAt = r.drinkAt {
                    metric("Hypothetical drink at bedtime", mg(hypothetical), source: "\(S.enteredMg(r.amountMg!)) at \(text.fullDateTime(drinkAt)) · not recorded")
                    if let combined = r.combinedMg, let threshold = r.thresholdMg {
                        metric("Combined at bedtime", mg(combined), source: "Your threshold: \(S.enteredMg(threshold))")
                        let within = combined <= threshold
                        StatusBadge(text: within ? "At or under your threshold" : "Above your threshold", tone: within ? .success : .warning)
                    }
                } else {
                    metric("Hypothetical drink at bedtime", "No time entered", source: "Add a drink time to see its modeled contribution.")
                }
            }
            latest(r)
            if !r.problems.isEmpty && !active {
                ForEach(r.problems, id: \.self) { problem in
                    Label(problem.message(timeZone: snapshot.timeZone), systemImage: StatusTone.warning.symbol)
                        .font(.footnote).foregroundStyle(Palette.textSecondary)
                }
            }
            DisclosureGroup("Assumptions") {
                VStack(alignment: .leading, spacing: Metrics.xxs) {
                    Text("Half-life \(numberText(snapshot.halfLifeHours)) h. \(S.assumption)")
                    Text("Bedtime uses modeled caffeine only. Sleep, sensitivity and other factors aren’t measured here.")
                    Text("Model \(snapshot.modelVersion) · calculated \(text.fullDateTime(snapshot.capturedAt)) · \(snapshot.timeZone)")
                        .foregroundStyle(Palette.textSecondary)
                }
                .font(.footnote).padding(.top, Metrics.xxs)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The reminder outcome is the card header's badge; only "preview
    /// again" belongs to the result itself.
    @ViewBuilder private var resultBadge: some View {
        if snapshot?.reminder == .needsNewPreview { StatusBadge(text: "Changed · preview again", tone: .warning) }
    }

    /// The card header's badge: what actually happened to this scenario.
    static func header(state: AssistantCard.State, active: Bool, reminder: CutoffScenario.ReminderOutcome?, text: DateText) -> (text: String, tone: StatusTone) {
        switch reminder {
        case .scheduled(let fireAt, _): return ("Reminder scheduled · \(text.clockTime(fireAt))", .success)
        case .notAllowed, .failed: return ("Reminder not scheduled", .error)
        case .needsNewPreview, nil: break
        }
        switch state {
        case .expired: return ("Expired", .warning)
        case .ready where active: return ("Scenario", .info)
        default: return ("Closed", .neutral)
        }
    }

    @ViewBuilder private func latest(_ r: S.Result) -> some View {
        let amount = r.amountMg.map(S.enteredMg) ?? ""
        let threshold = r.thresholdMg.map(S.enteredMg) ?? ""
        switch r.latest {
        case .unavailable:
            metric("Latest hypothetical time", r.problems.contains(.invalidHalfLife) ? "Can’t calculate" : "Needs inputs", source: S.latestUnavailableText(r.problems))
        case .needsAmount:
            metric("Latest hypothetical time", "No amount entered", source: "Enter a hypothetical amount to see a time.")
        case .feasible(let time):
            metric("Latest hypothetical time", text.fullDateTime(time), source: "For \(amount) to keep bedtime at or under \(threshold) in this scenario · \(zoneLabel(time))")
        case .passed(let time):
            metric("Latest hypothetical time", "Already passed", source: "In this scenario it was \(text.fullDateTime(time)). \(amount) from now on models above \(threshold) at bedtime.")
        case .thresholdReachedByRecords:
            metric("Latest hypothetical time", "None", source: "Existing records already model at or above \(threshold) at bedtime.")
        case .unreachable:
            metric("Latest hypothetical time", "No finite time", source: "Modeled caffeine halves but never reaches 0 mg, so a 0 mg threshold can’t be met.")
        }
    }

    // MARK: Reminder

    @ViewBuilder private var reminder: some View {
        if let preview {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                SectionLabel(text: "Reminder preview")
                Text(preview.content.title).font(Typography.evidence.weight(.semibold))
                Text(preview.content.body).font(.footnote)
                metric("Once, at", text.fullDateTime(preview.content.fireAt), source: "\(zoneLabel(preview.content.fireAt)) · your daily cutoff reminder is unchanged")
                VStack(spacing: Metrics.xxs) {
                    Button(assistant.savingCutoffReminder ? "Saving…" : "Save reminder") {
                        Task { await assistant.saveCutoffReminder(app: app) }
                    }
                    .buttonStyle(.auroraPrimary).disabled(assistant.savingCutoffReminder)
                    .accessibilityIdentifier("cutoff-reminder-save")
                    Button("Not now") { assistant.cancelCutoffPreview() }
                        .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
                        .disabled(assistant.savingCutoffReminder)
                }
            }
            .padding(Metrics.sm)
            .background(Palette.cardMuted, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
            .transition(Motion.stateTransition(reduceMotion: reduceMotion))
        } else if let snapshot, case .feasible = snapshot.result.latest, !inputsChanged {
            Button("Preview a one-time reminder") { field = nil; assistant.previewCutoffReminder(app: app) }
                .buttonStyle(.auroraSecondary).accessibilityIdentifier("cutoff-reminder-preview")
        }
    }

    // MARK: Rows

    private func mg(_ value: Double) -> String {
        value > 0 && value < 1 ? "under 1 mg" : "\(numberText(jsRound(value))) mg"
    }

    private func zoneLabel(_ ms: Millis) -> String {
        [zone.identifier, zone.abbreviation(for: date(ms))].compactMap { $0 }.joined(separator: " · ")
    }

    private func provenance(_ existing: S.Existing) -> String {
        var parts = ["\(existing.recordedCount) recorded \(existing.recordedCount == 1 ? "entry" : "entries")"]
        if existing.includesSample { parts.append("\(existing.sampleCount) Sample Data") }
        if existing.excludedFutureCount > 0 { parts.append("\(existing.excludedFutureCount) dated later not included") }
        return parts.joined(separator: " · ")
    }

    private func metric(_ label: String, _ value: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xxs) {
            valueRow(label, value, spoken: value.replacingOccurrences(of: " mg", with: " milligrams"))
            Text(source).font(Typography.source).foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, Metrics.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value.replacingOccurrences(of: " mg", with: " milligrams")). \(source.replacingOccurrences(of: " mg", with: " milligrams"))")
    }

    /// Label leading, value trailing; stacked when large text no longer fits.
    private func valueRow(_ label: String, _ value: String, spoken: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
                Text(label).font(Typography.label).foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
                Text(value).font(Typography.value).monospacedDigit().multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: Metrics.xxs) {
                Text(label).font(Typography.label).foregroundStyle(Palette.textSecondary)
                Text(value).font(Typography.value).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(spoken)")
    }
}
