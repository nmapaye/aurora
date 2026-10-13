import AuroraCore
import SwiftUI

struct AssistantCardView: View {
    let message: ConversationMessage
    let card: AssistantCard
    @Environment(AppModel.self) private var app
    @Environment(AssistantModel.self) private var assistant
    @State private var metric = "Caffeine"
    @State private var days = 7
    @State private var query = ""
    @State private var source = "All sources"
    @State private var historyDays = 0
    @State private var historyLimit = 30
    @State private var editingDose: DoseSheet?
    @State private var editingSleep: SleepSheet?
    @FocusState private var field: CardField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set when this card turns Saved while on screen, for the save moment.
    @State private var justSaved = false
    @State private var editingWakeReminders = false

    private enum CardField: Hashable { case amount, source, note, search }

    private var snapshotClock: LocalClock { LocalClock(timeZone: TimeZone(identifier: card.timeZone) ?? .current) }
    private var snapshotText: DateText { .localized(timeZone: snapshotClock.timeZone) }
    private var active: Bool { assistant.activeCards.contains(message.id) && card.state == .ready }
    private var draftActive: Bool { active && assistant.pendingMessageID == message.id }
    /// The open check-in editor states what a rating is; a summary saying the
    /// same sentence above it is skipped. Corrections still show their summary.
    private var repeatsCheckInLabel: Bool {
        card.kind == .energyCheckIn && draftActive && assistant.pendingCheckIn != nil && card.summary == EnergyCheckIn.kindLabel
    }

    /// The card's own summary line; energy and briefing cards say it in their
    /// content, and an open check-in editor already states it.
    private var showsSummary: Bool {
        !card.summary.isEmpty && ![.energy, .briefing, .energyProjection].contains(card.kind) && !repeatsCheckInLabel
    }

    // The body is split into members so each is type-checked on its own;
    // Xcode 26.6 gave up on it as one expression.
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            cardContent
            if card.kind != .clarification { captureRow }
        }
        .onChange(of: card.state, stateChanged)
        // Save or Discard removes the focused field, which clears focus too.
        .onChange(of: field, focusChanged)
        .onDisappear { assistant.cardFocus(message.id, focused: false) }
        .sheet(item: $editingDose, content: doseEditor)
        .sheet(item: $editingSleep, content: sleepEditor)
    }

    private func stateChanged(from old: AssistantCard.State, to new: AssistantCard.State) {
        justSaved = old == AssistantCard.State.ready && new == AssistantCard.State.saved
    }

    private func focusChanged(from _: CardField?, to value: CardField?) {
        assistant.cardFocus(message.id, focused: value != nil)
    }

    @ViewBuilder private var cardContent: some View {
        if card.kind == .calendar {
            calendar
        } else {
            Card {
                header
                if showsSummary {
                    Text(card.summary).font(Typography.explanation).foregroundStyle(Palette.textSecondary)
                }
                content
            }
            // Draft → saved and saved → removed change the card in place;
            // the conversation never re-animates a card's entrance.
            .animation(Motion.stateChange(reduceMotion: reduceMotion), value: card.state)
            .animation(Motion.stateChange(reduceMotion: reduceMotion), value: draftActive)
        }
    }

    private var captureRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack { captureLabel; Spacer(); refreshButton }
            VStack(alignment: .leading, spacing: Metrics.xs) { captureLabel; refreshButton }
        }
    }

    @ViewBuilder private func doseEditor(_ mode: DoseSheet) -> some View {
        if case .edit(let original) = mode {
            DoseEntrySheet(mode: mode, draft: CaffeineLog.editDraft(for: original)) { result in
                finishDoseEdit(original, result)
            }
        }
    }

    private func finishDoseEdit(_ original: Dose, _ result: DoseEntrySheet.Result) {
        guard app.state.doses.first(where: { $0.id == original.id }) == original else { assistant.failure = "This record changed. Refresh history before editing."; return }
        switch result {
        case .saved(let draft):
            app.correctDose(id: original.id, with: draft)
            if app.mutationFailure == nil { assistant.receipt(recordID: original.id, kind: "caffeine", app: app, title: "Caffeine updated") }
            else { assistant.failure = app.mutationFailure }
        case .deleted:
            app.deleteDose(id: original.id)
            if app.mutationFailure == nil { assistant.appendRemoval("Caffeine entry deleted on this device.", doseID: original.id, app: app) }
            else { assistant.failure = app.mutationFailure }
        case .cancelled: break
        }
    }

    @ViewBuilder private func sleepEditor(_ mode: SleepSheet) -> some View {
        if case .edit(let original) = mode {
            SleepEntrySheet(mode: mode) { draft in
                guard app.state.sleeps.first(where: { $0.id == original.id }) == original else { assistant.failure = "This record changed. Refresh history before editing."; return }
                app.correctManualSleep(id: original.id, with: draft)
                if app.mutationFailure == nil { assistant.receipt(recordID: original.id, kind: "sleep", app: app, title: "Sleep updated") }
                else { assistant.failure = app.mutationFailure }
            } onDelete: {
                guard app.state.sleeps.first(where: { $0.id == original.id }) == original else { assistant.failure = "This record changed. Refresh history before deleting."; return }
                app.deleteManualSleep(id: original.id)
                if app.mutationFailure == nil { assistant.append("Sleep entry deleted.") }
                else { assistant.failure = app.mutationFailure }
            }
        }
    }
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) { title; Spacer(minLength: 0); draftBadge }
            VStack(alignment: .leading, spacing: Metrics.xs) { title; draftBadge }
        }
    }
    private var title: some View {
        Label(card.title, systemImage: symbol).font(Typography.cardTitle)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("assistant-card-\(card.kind.rawValue)")
    }
    /// Drafts say where they stand; receipts already do through their title.
    @ViewBuilder private var draftBadge: some View {
        if (card.kind == .energy || card.kind == .energyProjection) && card.energy != nil && card.state == .ready
            && app.now - card.capturedAt > EnergyCardTiming.staleAfterMs {
            // Old snapshots keep their results; this only says they are old.
            // The badge itself refreshes, so "Refresh" is never a riddle.
            Button { assistant.refresh(card, app: app) } label: {
                Label("Earlier snapshot · Tap to refresh", systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(StatusTone.warning.foreground)
                    .padding(.horizontal, Metrics.sm).padding(.vertical, Metrics.xxs)
                    .background(StatusTone.warning.background, in: Capsule())
            }
            .buttonStyle(.auroraPress)
            .disabled(assistant.processing)
        }
        if card.kind == .cutoffScenario {
            let header = CutoffScenarioCardView.header(state: card.state, active: draftActive, reminder: card.cutoff?.reminder, text: snapshotText)
            StatusBadge(text: header.text, tone: header.tone)
        }
        if card.kind == .caffeineDraft || card.kind == .sleepDraft || card.kind == .energyCheckIn {
            switch card.state {
            case .ready: draftActive ? StatusBadge(text: "Review before saving", tone: .info) : StatusBadge(text: "Closed")
            case .saved: SavedBadge(celebrate: justSaved)
            case .undone: StatusBadge(text: "Removed")
            case .expired: StatusBadge(text: "Expired", tone: .warning)
            case .discarded: StatusBadge(text: "Discarded")
            case .failed: StatusBadge(text: "Not saved", tone: .error)
            case .loading: EmptyView()
            }
        }
    }
    /// The person's caffeine reminders after waking, with the next one.
    @ViewBuilder private var wakeReminderRow: some View {
        let settings = app.state.prefs.wakeReminders?.normalized()
        let on = settings?.enabled == true && settings?.offsetsMinutes.isEmpty == false
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline) {
                Label("Caffeine after waking", systemImage: "alarm").font(Typography.label).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(on ? settings!.offsetsMinutes.map { "+" + WakeReminders.offsetText($0) }.joined(separator: ", ") : "Off")
                    .font(Typography.value.monospacedDigit()).foregroundStyle(on ? Palette.textPrimary : Palette.textSecondary)
            }
            if on, let next = app.nextWakeReminder {
                Text("Next \(app.clock.dayKey(next.fireAt) == app.clock.dayKey(app.now) ? "" : "tomorrow ")\(app.text.clockTime(next.fireAt))")
                    .font(Typography.source).foregroundStyle(Palette.textSecondary)
            }
            Button(on ? "Change" : "Set up") { editingWakeReminders = true }
                .buttonStyle(on ? AnyButtonStyle(.auroraSecondary) : AnyButtonStyle(.auroraPrimary))
                .accessibilityIdentifier("assistant-wake-reminders-edit")
        }
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $editingWakeReminders) { NavigationStack { WakeRemindersView() } }
    }
    /// When the card's records were read: just the time today, the day
    /// otherwise, and the zone only if it isn't the current one.
    private var captureText: String {
        let sameZone = snapshotClock.timeZone.secondsFromGMT() == TimeZone.current.secondsFromGMT()
        let today = app.clock.dayKey(card.capturedAt) == app.clock.dayKey(app.now)
        let when = today ? snapshotText.clockTime(card.capturedAt) : snapshotText.fullDateTime(card.capturedAt)
        return sameZone ? when : "\(when) · \(snapshotClock.timeZone.abbreviation() ?? card.timeZone)"
    }
    private var captureLabel: some View {
        Text(captureText)
            .font(.caption2).foregroundStyle(Palette.textSecondary)
    }
    @ViewBuilder private var refreshButton: some View {
        if card.refreshIntent != nil {
            let label = [.caffeineDraft, .sleepDraft, .calendar, .energyCheckIn].contains(card.kind) ? "New review" : "Refresh"
            Button { assistant.refresh(card, app: app) } label: {
                Label(label, systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, Metrics.sm)
                    .frame(minHeight: 32)
                    .background(Palette.selectionFill, in: Capsule())
                    .frame(minHeight: Metrics.minimumTouchTarget)
            }
            .buttonStyle(.auroraPress)
            .foregroundStyle(Palette.tint)
            .disabled(assistant.processing).accessibilityIdentifier("assistant-refresh-\(card.kind.rawValue)")
        }
    }
    private var symbol: String {
        switch card.kind {
        case .caffeineDraft: "cup.and.saucer"
        case .sleepDraft: "moon"
        case .energy: "sparkles"
        case .trends: "chart.bar"
        case .calendar: "calendar"
        case .reaction: "hand.tap"
        case .history: "clock.arrow.circlepath"
        case .exports: "square.and.arrow.up"
        case .briefing: "sun.horizon"
        case .reminders: "bell"
        case .clarification: "sparkle"
        case .energyProjection: "chart.xyaxis.line"
        case .energyCheckIn: "hand.raised"
        case .cutoffScenario: "moon.zzz"
        case .receipt: card.state == .undone ? "arrow.uturn.backward" : "checkmark.circle"
        }
    }
    @ViewBuilder private var content: some View {
        switch card.kind {
        case .caffeineDraft: caffeineEditor
        case .sleepDraft: sleepEditor
        case .energy, .briefing:
            evidence
            if card.kind == .briefing {
                if card.state == .loading { ProgressView("Reading selected commitments…") }
                if card.state == .failed { Text(card.summary).font(.footnote).foregroundStyle(Palette.destructive) }
                if card.state != .loading && card.commitments.isEmpty { Text("No commitments captured. Review calendars for current availability.").font(.caption).foregroundStyle(Palette.textSecondary) }
                ForEach(card.commitments, id: \.identity) { event in
                    Label { VStack(alignment: .leading) { Text(event.title); Text(event.start.formatted(date: .abbreviated, time: .shortened) + " · " + event.timeZone).font(.caption).foregroundStyle(Palette.textSecondary) } } icon: { Image(systemName: "calendar") }
                }
                Button("Review my day") { assistant.send("Review calendar", app: app) }.buttonStyle(.auroraSecondary)
            }
        case .trends: trends
        case .calendar: EmptyView()
        case .reaction:
            metricRows
            Button(card.state == .saved ? "Take another test" : "Start 60-second test") { assistant.historySheet = .reactionTest }
                .buttonStyle(.auroraPrimary).accessibilityIdentifier("assistant-reaction-start")
        case .history: history
        case .exports: exports
        case .energyProjection: projection
        case .energyCheckIn: checkInEditor
        case .cutoffScenario: CutoffScenarioCardView(message: message, card: card, active: draftActive)
        case .reminders:
            // Each setting appears once, as its own control.
            wakeReminderRow
            Toggle("Proactive suggestions", isOn: Binding(get: { assistant.conversation.preferences.proactive }, set: { enabled in
                assistant.conversation.preferences.proactive = enabled; assistant.save()
                Task { await assistant.syncBriefingNotification(prompt: enabled) }
            }))
            Toggle("Morning briefing", isOn: Binding(get: { assistant.conversation.preferences.morningBriefing }, set: { enabled in
                assistant.conversation.preferences.morningBriefing = enabled; assistant.save()
                Task { await assistant.syncBriefingNotification(prompt: enabled) }
            })).disabled(!assistant.conversation.preferences.proactive)
            Toggle("Cutoff reminder", isOn: Binding(get: { app.state.prefs.notifyCutoff }, set: { enabled in
                Task { await app.setReminder(enabled: enabled) }
            }))
            if app.reminderStatus == .denied { Text("Notifications are unavailable. Check iOS notification settings.").font(.footnote).foregroundStyle(Palette.destructive) }
            Button("Manage reminders") { assistant.showAssistantSettings = true }.buttonStyle(.auroraPrimary)
            Button("Cutoff reminder settings") { assistant.historySheet = .settings }.buttonStyle(.auroraSecondary)
        case .clarification:
            ForEach([("Record caffeine", "Log caffeine"), ("Record sleep", "Log sleep"), ("Understand my energy", "How is my energy?"), ("See my modeled day", "Show my energy curve"), ("Check in my energy", "Check in my energy"), ("Explore trends", "Show this week"), ("Review my day", "Review calendar")], id: \.0) { label, prompt in
                Button { assistant.send(prompt, app: app) } label: { HStack { Text(label); Spacer(); Image(systemName: "chevron.right") }.frame(minHeight: Metrics.minimumTouchTarget) }
                    .buttonStyle(.auroraPress).foregroundStyle(Palette.tint).disabled(assistant.processing)
            }
        case .receipt where card.recordKind == "checkin":
            checkInReceipt
        case .receipt:
            ForEach(card.records, id: \.identity) { row in
                let removed = card.state == .undone
                VStack(alignment: .leading, spacing: Metrics.xxs) {
                    valueRow(row.title, row.detail, labelFont: Typography.evidence, labelColor: removed ? Palette.textSecondary : Palette.textPrimary)
                        .strikethrough(removed)
                    Text(row.source + " · " + snapshotText.fullDateTime(row.date)).font(Typography.source).foregroundStyle(Palette.textSecondary)
                }
                .foregroundStyle(removed ? Palette.textSecondary : Palette.textPrimary)
                .accessibilityElement(children: .combine)
            }
            metricRows
            if card.state == .saved && card.recordID != nil && !card.title.lowercased().contains("updated") {
                Button("Undo entry") { assistant.undoReceipt(message, app: app) }.buttonStyle(.auroraSecondary).accessibilityIdentifier("assistant-undo")
                    .transition(Motion.stateTransition(reduceMotion: reduceMotion))
            }
        }
    }
    /// Label leading, quantity trailing on one baseline; stacks when the text
    /// size no longer fits both on a line.
    private func valueRow(_ label: String, _ value: String, labelFont: Font = Typography.label, labelColor: Color = Palette.textSecondary, valueFont: Font = Typography.value) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
                Text(label).font(labelFont).foregroundStyle(labelColor)
                Spacer(minLength: 0)
                Text(value).font(valueFont).monospacedDigit().multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: Metrics.xxs) {
                Text(label).font(labelFont).foregroundStyle(labelColor)
                Text(value).font(valueFont).monospacedDigit()
            }
        }
    }
    private var metricRows: some View {
        ForEach(card.metrics) { item in
            VStack(alignment: .leading, spacing: Metrics.xxs) {
                valueRow(item.label, item.value)
                Text(item.source).font(Typography.source).foregroundStyle(Palette.textSecondary)
                if !item.detail.isEmpty { Text(item.detail).font(.footnote).foregroundStyle(Palette.textSecondary) }
            }.padding(.vertical, Metrics.xxs).accessibilityElement(children: .combine)
        }
    }
    private var evidence: some View {
        VStack(alignment: .leading, spacing: Metrics.md) {
            if card.kind == .energy && card.state == .failed {
                Text(card.summary).font(.footnote).foregroundStyle(Palette.destructive)
            }
            // The overview: the headline number, then what it means for the day.
            ForEach(card.metrics.filter { $0.id == "alertness" || card.kind != .energy }) { item in
                metricHero(item)
            }
            if let outlook = card.energy?.outlook { EnergyOutlookView(outlook: outlook, text: snapshotText) }
            // Missing inputs stay visible, with a way to add them.
            ForEach(card.metrics.filter { $0.missing && ($0.id == "sleep" || $0.id == "caffeine") }) { item in
                Button(item.id == "sleep" ? "Record sleep" : "Record caffeine") { assistant.send(item.id == "sleep" ? "Log sleep" : "Log caffeine", app: app) }
                    .buttonStyle(.auroraSecondary)
            }
            // Everything else only when asked for.
            if card.kind == .energy {
                DisclosureGroup("What’s recorded") {
                    ForEach(card.metrics.filter { $0.id != "alertness" }) { metricHero($0) }
                }
                if let energy = card.energy {
                    DisclosureGroup("What the model used") { EnergyEvidenceSections(snapshot: energy, text: snapshotText) }
                }
            }
            DisclosureGroup("What this means") {
                Text(EnergyExplainer.meaning).font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func metricHero(_ item: AssistantCard.Metric) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xxs) {
            Text(item.label).font(Typography.label).foregroundStyle(Palette.textSecondary)
            Text(item.value).font(Typography.heroValue).monospacedDigit()
            if !item.source.isEmpty { Text(item.source).font(Typography.source).foregroundStyle(Palette.textSecondary) }
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder private var projection: some View {
        if let energy = card.energy, let projection = energy.projection, !projection.points.isEmpty {
            if card.state == .failed { Text(card.summary).font(.footnote).foregroundStyle(Palette.destructive) }
            let chart = EnergyTimelineChart(snapshot: energy, projection: projection, text: snapshotText, timeZone: snapshotClock.timeZone)
            chart
            if let outlook = energy.outlook { EnergyOutlookView(outlook: outlook, text: snapshotText) }
            DisclosureGroup("What’s recorded in this window") { chart.observations.padding(.top, Metrics.xs) }
            DisclosureGroup("What the model used") { EnergyEvidenceSections(snapshot: energy, text: snapshotText) }
            DisclosureGroup("What this means") {
                Text(EnergyExplainer.meaning).font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(card.summary.isEmpty ? "This snapshot has no curve. Refresh for a current one." : card.summary)
                .font(.footnote).foregroundStyle(card.state == .failed ? Palette.destructive : Palette.textSecondary)
        }
    }
    @ViewBuilder private var checkInEditor: some View {
        if draftActive, let draft = assistant.pendingCheckIn {
            VStack(alignment: .leading, spacing: Metrics.md) {
                Text(EnergyCheckIn.kindLabel).font(Typography.explanation).foregroundStyle(Palette.textSecondary)
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text(EnergyCheckIn.scaleLabel).font(Typography.label).foregroundStyle(Palette.textSecondary)
                    Picker("Your rating", selection: Binding(get: { assistant.pendingCheckIn?.rating }, set: { assistant.pendingCheckIn?.rating = $0 })) {
                        ForEach(Array(EnergyCheckIn.scale), id: \.self) { value in
                            Text("\(value)").tag(Optional(value)).accessibilityLabel("\(value), \(EnergyCheckIn.label(forRating: value) ?? "")")
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: Metrics.minimumTouchTarget)
                    .accessibilityIdentifier("assistant-checkin-rating")
                    Text(draft.rating.map { EnergyCheckIn(id: draft.id, recordedAt: draft.recordedAt, rating: $0).ratingText } ?? "No rating chosen")
                        .font(Typography.value).monospacedDigit()
                        .accessibilityIdentifier("assistant-checkin-rating-value")
                }
                DatePicker(selection: Binding(get: { Date(timeIntervalSince1970: (assistant.pendingCheckIn?.recordedAt ?? app.now) / 1000) }, set: { assistant.pendingCheckIn?.recordedAt = $0.timeIntervalSince1970 * 1000 }), in: ...Date.now) {
                    Text("Time").font(Typography.label).foregroundStyle(Palette.textSecondary)
                }
                .frame(minHeight: Metrics.minimumTouchTarget)
                if draft.rating != nil, let problem = draft.validate(now: AppModel.currentMillis()).message { fieldProblem(problem) }
                Text(EnergyCheckIn.sourceLabel + " · local time").font(Typography.source).foregroundStyle(Palette.textSecondary)
                LabeledField(label: "Note") {
                    TextField("Optional note", text: Binding(get: { assistant.pendingCheckIn?.note ?? "" }, set: { assistant.pendingCheckIn?.note = $0 }))
                        .font(Typography.evidence).focused($field, equals: .note).accessibilityIdentifier("assistant-checkin-note")
                }
                draftActions(save: draft.original == nil ? "Save check-in" : "Save correction", saveID: "assistant-checkin-save", disabled: false) { assistant.saveCheckIn(app: app) }
                recentCheckIns
            }
            .transition(Motion.stateTransition(reduceMotion: reduceMotion))
        } else {
            closedDraft(card.state == .saved ? "Saved. See the receipt below." : "This check-in is closed. Start a new review to record a rating.")
            recentCheckIns
        }
    }
    @ViewBuilder private var recentCheckIns: some View {
        if let recent = card.checkIn?.recent {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                SectionLabel(text: "Your check-ins · last 7 days")
                if recent.isEmpty { Text("No check-ins in the last 7 days.").font(.footnote).foregroundStyle(Palette.textSecondary) }
                ForEach(recent.prefix(5)) { CheckInRow(checkIn: $0, text: snapshotText) }
            }
        }
    }
    @ViewBuilder private var checkInReceipt: some View {
        if let info = card.checkIn, let saved = info.saved {
            let undone = card.state == .undone
            VStack(alignment: .leading, spacing: Metrics.xxs) {
                valueRow("Energy check-in", saved.ratingText, labelFont: Typography.evidence, labelColor: undone ? Palette.textSecondary : Palette.textPrimary)
                    .strikethrough(undone)
                Text(EnergyCheckIn.sourceLabel + " · " + snapshotText.fullDateTime(saved.recordedAt)).font(Typography.source).foregroundStyle(Palette.textSecondary)
                if let note = saved.note { Text(note).font(.footnote).foregroundStyle(Palette.textSecondary) }
                if let previous = info.previous {
                    Text("Before the correction: \(previous.ratingText)").font(.footnote).foregroundStyle(Palette.textSecondary)
                }
            }
            .foregroundStyle(undone ? Palette.textSecondary : Palette.textPrimary)
            .accessibilityElement(children: .combine)
            if card.state == .saved {
                VStack(spacing: Metrics.xxs) {
                    Button(info.previous == nil ? "Undo check-in" : "Undo correction") { assistant.undoCheckIn(message, app: app) }
                        .buttonStyle(.auroraSecondary).accessibilityIdentifier("assistant-checkin-undo")
                    Button("Edit check-in") { assistant.editCheckIn(message, app: app) }
                        .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
                        .disabled(assistant.processing).accessibilityIdentifier("assistant-checkin-edit")
                }
                .transition(Motion.stateTransition(reduceMotion: reduceMotion))
            }
        }
    }
    /// One-tap drinks, favorites first: each fills the drink and amount,
    /// which stay editable before Save.
    private func drinkChips(selected draft: CustomDoseDraft) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.xs) {
                ForEach(CaffeinePreset.ordered(favorites: app.state.prefs.favoriteDrinkIDs)) { preset in
                    let chosen = draft.source == preset.label && draft.mg == numberText(preset.mg)
                    Button {
                        assistant.pendingDraft?.source = preset.label
                        assistant.pendingDraft?.mg = numberText(preset.mg)
                    } label: {
                        Label("\(preset.label) · \(numberText(preset.mg)) mg", systemImage: preset.symbol)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, Metrics.sm)
                            .frame(minHeight: Metrics.minimumTouchTarget)
                            .foregroundStyle(chosen ? Palette.primaryButtonText : Palette.textPrimary)
                            .background(chosen ? Palette.tint : Palette.cardMuted, in: Capsule())
                    }
                    .buttonStyle(.auroraPress)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    .accessibilityIdentifier("assistant-drink-\(preset.id)")
                }
            }
        }
        .scrollClipDisabled()
    }
    @ViewBuilder private var caffeineEditor: some View {
        if draftActive, let draft = assistant.pendingDraft {
            VStack(alignment: .leading, spacing: Metrics.md) {
                drinkChips(selected: draft)
                LabeledField(label: "Amount", unit: "mg") {
                    TextField("Amount in mg", text: Binding(get: { assistant.pendingDraft?.mg ?? "" }, set: { assistant.pendingDraft?.mg = $0 }))
                        .keyboardType(.numberPad).font(Typography.evidence).monospacedDigit().focused($field, equals: .amount)
                        .accessibilityIdentifier("assistant-dose-amount")
                }
                // Mirrors Save's own validation once something is typed; Save
                // stays enabled and still reports an empty amount itself.
                if !draft.mg.isEmpty, let problem = CaffeineLog.validate(draft, now: AppModel.currentMillis()).message {
                    fieldProblem(problem)
                }
                LabeledField(label: "Drink or source") {
                    TextField("Drink or source", text: Binding(get: { assistant.pendingDraft?.source ?? "" }, set: { assistant.pendingDraft?.source = $0 }))
                        .font(Typography.evidence).focused($field, equals: .source).accessibilityIdentifier("assistant-dose-source")
                }
                DatePicker(selection: Binding(get: { Date(timeIntervalSince1970: (assistant.pendingDraft?.timestamp ?? app.now) / 1000) }, set: { assistant.pendingDraft?.timestamp = $0.timeIntervalSince1970 * 1000 }), in: ...Date.now) {
                    Text("Recorded time").font(Typography.label).foregroundStyle(Palette.textSecondary)
                }
                .frame(minHeight: Metrics.minimumTouchTarget)
                Text("Manual · local time").font(Typography.source).foregroundStyle(Palette.textSecondary)
                draftActions(save: "Save entry", saveID: "assistant-dose-save", disabled: false) { assistant.saveDose(app: app) }
            }
            .transition(Motion.stateTransition(reduceMotion: reduceMotion))
        } else { closedDraft(card.state == .saved ? "Saved. See the receipt below." : "This draft is closed. Start a new review to record an entry.") }
    }
    private func fieldProblem(_ text: String) -> some View {
        Label(text, systemImage: StatusTone.error.symbol).font(.footnote).foregroundStyle(Palette.destructive)
    }
    /// Save leads; Discard is the quiet way out. Stacked so both keep a full
    /// touch target at every text size.
    private func draftActions(save: String, saveID: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: Metrics.xxs) {
            Button(save, action: action).buttonStyle(.auroraPrimary).accessibilityIdentifier(saveID).disabled(disabled)
            Button("Discard") { assistant.discardDraft() }
                .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
        }
        .padding(.top, Metrics.xxs)
    }
    private func closedDraft(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            metricRows
            Text(note).font(.footnote).foregroundStyle(Palette.textSecondary)
        }
        .transition(Motion.stateTransition(reduceMotion: reduceMotion))
    }
    @ViewBuilder private var sleepEditor: some View {
        if draftActive, let draft = assistant.pendingSleep {
            VStack(alignment: .leading, spacing: Metrics.md) {
                DatePicker(selection: sleepDate(\.start), in: ...Date.now) { Text("Start").font(Typography.label).foregroundStyle(Palette.textSecondary) }
                    .frame(minHeight: Metrics.minimumTouchTarget).accessibilityIdentifier("assistant-sleep-start")
                DatePicker(selection: sleepDate(\.end), in: ...Date.now) { Text("End").font(Typography.label).foregroundStyle(Palette.textSecondary) }
                    .frame(minHeight: Metrics.minimumTouchTarget).accessibilityIdentifier("assistant-sleep-end")
                HStack(alignment: .firstTextBaseline) {
                    Text("Duration").font(Typography.label).foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: Metrics.sm)
                    Text(formatHoursMinutes(durationMs: max(0, draft.end - draft.start))).font(Typography.value).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                if let problem = ManualSleep.validate(start: draft.start, end: draft.end, now: AppModel.currentMillis()).message { fieldProblem(problem) }
                Text("Manual · local time").font(Typography.source).foregroundStyle(Palette.textSecondary)
                LabeledField(label: "Note") {
                    TextField("Optional note", text: Binding(get: { assistant.pendingSleep?.note ?? "" }, set: { assistant.pendingSleep?.note = $0 })).font(Typography.evidence).focused($field, equals: .note)
                }
                draftActions(save: "Save sleep", saveID: "assistant-sleep-save", disabled: ManualSleep.validate(start: draft.start, end: draft.end, now: AppModel.currentMillis()) != .valid) { assistant.saveSleep(app: app) }
            }
            .transition(Motion.stateTransition(reduceMotion: reduceMotion))
        } else { closedDraft(card.state == .saved ? "Saved. See the receipt below." : "This draft is closed. Start a new review to record sleep.") }
    }
    private func sleepDate(_ key: WritableKeyPath<ManualSleep.Draft, Millis>) -> Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: (assistant.pendingSleep?[keyPath: key] ?? app.now) / 1000) }, set: { assistant.pendingSleep?[keyPath: key] = $0.timeIntervalSince1970 * 1000 })
    }
    @ViewBuilder private var trends: some View {
        Picker("Recorded signal", selection: $metric) { ForEach(["Caffeine", "Sleep", "Reaction"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("assistant-trend-metric")
        Picker("Range", selection: $days) { Text("Week").tag(7); Text("Month").tag(30) }.pickerStyle(.segmented).accessibilityIdentifier("assistant-trend-range")
        if let series = card.series.first(where: { $0.metric == metric && $0.days == days }) {
            DailyBarChart(title: metric == "Caffeine" && days == 7 ? "Recorded caffeine · this week" : "Recorded \(metric.lowercased()) · \(days) days", days: series.points.map {
                .init(date: $0.date, value: $0.value, title: snapshotText.weekdayDate($0.date), readout: $0.detail, isSample: $0.sample)
            }, unit: series.unit, accent: metric == "Caffeine" ? Palette.caffeineAccent : Palette.tint, accessibilitySummary: series.summary, emptyMessage: "No \(metric.lowercased()) recorded in this range.").environment(\.timeZone, snapshotClock.timeZone)
            Text(series.comparison).font(.footnote).foregroundStyle(Palette.textSecondary)
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            TextField("Search records", text: $query).textFieldStyle(.roundedBorder).focused($field, equals: .search).accessibilityIdentifier("assistant-history-search")
            Picker("Date range", selection: $historyDays) { Text("7d").tag(7); Text("30d").tag(30); Text("All").tag(0) }.pickerStyle(.segmented)
            Picker("Source", selection: $source) { ForEach(["All sources", "Manual", "Health", "Sample Data", "Recorded"], id: \.self) { Text($0).tag($0) } }
            if filteredRecords.isEmpty { Text("No matching records in this snapshot.").foregroundStyle(Palette.textSecondary) }
            ForEach(Array(filteredRecords.prefix(historyLimit)), id: \.identity) { row in
                Button { edit(row) } label: {
                    HStack(spacing: Metrics.sm) {
                        VStack(alignment: .leading, spacing: Metrics.xxs) {
                            Text(row.title + " · " + row.detail).font(.subheadline.weight(.medium)).monospacedDigit()
                            Text(snapshotText.weekdayDate(row.date) + " · " + row.source + (row.editable ? " · Edit" : " · Read-only")).font(Typography.source).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        if row.editable { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.textTertiary).accessibilityHidden(true) }
                    }.frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.auroraPress).disabled(!row.editable)
            }
            if filteredRecords.count > historyLimit { Button("Show more records (\(filteredRecords.count) total)") { historyLimit += 30 }.frame(minHeight: Metrics.minimumTouchTarget) }
        }
    }
    private var filteredRecords: [AssistantCard.Record] {
        let start = historyDays == 0 ? -Double.greatestFiniteMagnitude : snapshotClock.addingDays(-(historyDays - 1), to: snapshotClock.startOfDay(card.capturedAt))
        return card.records.filter { row in
            row.date >= start && (source == "All sources" || row.source == source) && (query.isEmpty || (row.title + " " + row.detail + " " + row.kind).localizedCaseInsensitiveContains(query))
        }
    }
    private func edit(_ row: AssistantCard.Record) {
        let current = AssistantCards.make(.history, state: app.state, now: app.now, clock: app.clock, text: app.text).records.first { $0.identity == row.identity }
        guard current == row else { assistant.failure = "This record changed. Refresh history before editing."; return }
        if row.kind == "caffeine", let dose = app.state.doses.first(where: { $0.id == row.id }), CaffeineLog.isEditable(dose) { editingDose = .edit(dose) }
        if row.kind == "sleep", let sleep = app.state.sleeps.first(where: { $0.id == row.id }), RecordID.isManualSleep(sleep.id) { editingSleep = .edit(sleep) }
    }
    private var exports: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            ShareLink(item: CSVFile(name: "aurora-caffeine-entries.csv", text: Export.doseEntriesCSV(app.state.doses, clock: app.clock)), preview: SharePreview("Caffeine entries")) { Label("Caffeine entries CSV", systemImage: "cup.and.saucer") }
            ShareLink(item: CSVFile(name: "aurora-sleep.csv", text: Export.sleepSessionsCSV(app.state.sleeps, clock: app.clock)), preview: SharePreview("Sleep records")) { Label("Sleep records CSV", systemImage: "moon") }
            ShareLink(item: CSVFile(name: "aurora-reaction-tests.csv", text: Export.vigilanceSessionsCSV(app.state.vigilanceSessions)), preview: SharePreview("Reaction tests")) { Label("Reaction tests CSV", systemImage: "hand.tap") }
            ShareLink(item: CSVFile(name: "aurora-energy-check-ins.csv", text: Export.energyCheckInsCSV(app.state.energyCheckIns, clock: app.clock)), preview: SharePreview("Energy check-ins")) { Label("Energy check-ins CSV", systemImage: "hand.raised") }
            ShareLink(item: CSVFile(name: "aurora-daily-caffeine.csv", text: Export.dailyTotalsCSV(Export.dailyTotalRows(app.state.doses, now: app.now, clock: app.clock))), preview: SharePreview("Daily caffeine totals")) { Label("Daily caffeine totals CSV", systemImage: "chart.bar") }
        }.buttonStyle(.auroraSecondary)
    }
    @ViewBuilder private var calendar: some View {
        if card.state == .loading {
            Card { Label(card.title, systemImage: "calendar").font(.headline); ProgressView("Reading selected commitments…"); Text("No changes have been made.").font(.caption) }
        } else {
            CalendarReviewCard(service: assistant.calendars, snapshot: card.commitments, editable: active, snapshotMessage: card.state == .failed ? card.summary : nil, onOutcome: { text, updated in
                var receipt = AssistantCard(kind: .receipt, capturedAt: app.now, title: updated == nil ? "Calendar change not confirmed" : "Calendar updated", summary: text)
                receipt.state = updated == nil ? .failed : .saved
                if let updated { receipt.commitments = [updated] }
                assistant.appendCard(receipt)
            }) { assistant.showCalendarSettings = true }
        }
    }
}

enum EnergyCardTiming {
    /// An energy snapshot older than this is labeled as earlier. Its
    /// results never change; Refresh captures a new one.
    static let staleAfterMs: Millis = hourMs
}
