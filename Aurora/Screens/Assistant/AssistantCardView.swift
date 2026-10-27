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
    @Environment(\.dynamicTypeSize) private var typeSize
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
            if card.kind != .clarification && card.kind != .welcome { captureRow }
        }
        .onChange(of: card.state, stateChanged)
        // Save or Discard removes the focused field, which clears focus too.
        .onChange(of: field, focusChanged)
        .onDisappear { assistant.cardFocus(message.id, focused: false) }
        .toolbar { keyboardDone }
        .sheet(item: $editingDose, content: doseEditor)
        .sheet(item: $editingSleep, content: sleepEditor)
    }

    /// The number pad has no return key; Done ends editing so the rest of
    /// the card, and its Save, can be reached. Only the card being edited
    /// adds it.
    @ToolbarContentBuilder private var keyboardDone: some ToolbarContent {
        if field != nil {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { field = nil }.accessibilityIdentifier("assistant-keyboard-done")
            }
        }
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
        // Redrawn once more when an energy snapshot turns earlier.
        TimelineView(.explicit(staleMoment)) { _ in
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) { title; Spacer(minLength: 0); draftBadge }
                VStack(alignment: .leading, spacing: Metrics.xs) { title; draftBadge }
            }
        }
    }
    /// The symbol is decoration: VoiceOver would read its own name ("Do Not
    /// Disturb" for the moon), so only the title is spoken.
    private var title: some View {
        Label { Text(card.title) } icon: { Image(systemName: symbol).accessibilityHidden(true) }
            .font(Typography.cardTitle)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            // One element: automation still finds the hidden symbol, and it
            // took the card's identifier ahead of the title.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("assistant-card-\(card.kind.rawValue)")
    }
    /// A ready energy snapshot can turn earlier; other cards never change with time.
    private var canTurnEarlier: Bool {
        (card.kind == .energy || card.kind == .energyProjection) && card.energy != nil && card.state == .ready
    }
    /// When a fresh energy snapshot turns earlier; empty otherwise. The badge
    /// reads the time only then: the app's per-minute `now` redrew the whole
    /// card, chart included, every minute.
    private var staleMoment: [Date] {
        let at = (card.capturedAt + EnergyCardTiming.staleAfterMs) / 1000 + 1
        return canTurnEarlier && at > Date.now.timeIntervalSince1970 ? [Date(timeIntervalSince1970: at)] : []
    }
    /// Drafts say where they stand; receipts already do through their title.
    @ViewBuilder private var draftBadge: some View {
        if canTurnEarlier && Date.now.timeIntervalSince1970 * 1000 - card.capturedAt > EnergyCardTiming.staleAfterMs {
            // Old snapshots keep their results; this only says they are old.
            // The badge itself refreshes, so "Refresh" is never a riddle.
            Button { assistant.refresh(card, app: app) } label: {
                Label { Text("Earlier snapshot") } icon: { Image(systemName: "arrow.clockwise").accessibilityHidden(true) }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(StatusTone.warning.foreground)
                    .padding(.horizontal, Metrics.sm).padding(.vertical, Metrics.xxs)
                    .background(StatusTone.warning.background, in: Capsule())
                    // The capsule stays compact; the whole 44 pt row is the target.
                    .frame(minHeight: Metrics.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.auroraPress)
            .disabled(assistant.processing)
            .accessibilityHint("Captures a current one.")
            .accessibilityIdentifier("assistant-earlier-snapshot")
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
    /// One capability as a tappable row; it sends the capability's request.
    /// At accessibility sizes the symbols go, so the title keeps the width
    /// and doesn't break mid-word.
    private func capabilityRow(_ capability: Capability, showsSymbol: Bool = false) -> some View {
        Button { assistant.send(capability.phrase, app: app) } label: {
            HStack(spacing: Metrics.xs) {
                if showsSymbol && !typeSize.isAccessibilitySize {
                    Image(systemName: capability.symbol).frame(width: 24).accessibilityHidden(true)
                }
                Text(capability.intent == .help && !showsSymbol ? "See everything I can do" : capability.title)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).accessibilityHidden(true)
            }
            .frame(minHeight: Metrics.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.auroraPress).foregroundStyle(Palette.tint).disabled(assistant.processing)
        .accessibilityIdentifier("capability-\(capability.intent.rawValue)")
    }
    /// The person's caffeine reminders after waking, with the next one.
    @ViewBuilder private var wakeReminderRow: some View {
        let settings = app.state.prefs.wakeReminders?.normalized()
        let on = settings?.enabled == true && settings?.offsetsMinutes.isEmpty == false
        let value = on ? settings!.offsetsMinutes.map { "+" + WakeReminders.offsetText($0) }.joined(separator: ", ") : "Off"
        VStack(alignment: .leading, spacing: Metrics.xs) {
            // The value goes under the label at accessibility sizes.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.xxs))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Metrics.sm))
            layout {
                Label { Text("Caffeine after waking") } icon: { Image(systemName: "alarm").accessibilityHidden(true) }
                    .font(Typography.label).foregroundStyle(Palette.textPrimary)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(value).font(Typography.value.monospacedDigit()).foregroundStyle(on ? Palette.textPrimary : Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
            if on, let next = app.nextWakeReminder {
                Text("Next \(app.clock.dayKey(next.fireAt) == app.clock.dayKey(app.now) ? "" : "tomorrow ")\(app.text.clockTime(next.fireAt))")
                    .font(Typography.source).foregroundStyle(Palette.textSecondary)
            }
            // The card's one primary action, while nothing is set up.
            Button(on ? "Change" : "Set up") { editingWakeReminders = true }
                .buttonStyle(on ? AnyButtonStyle(.auroraSecondary) : AnyButtonStyle(.auroraPrimary))
                .accessibilityIdentifier("assistant-wake-reminders-edit")
        }
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $editingWakeReminders) { NavigationStack { WakeRemindersView() } }
    }
    /// When the card's records were read: just the time today, the day
    /// otherwise, and the zone only if it isn't the current one.
    private func captureText(now: Date) -> String {
        let sameZone = snapshotClock.timeZone.secondsFromGMT() == TimeZone.current.secondsFromGMT()
        let today = app.clock.dayKey(card.capturedAt) == app.clock.dayKey(now.timeIntervalSince1970 * 1000)
        let when = today ? snapshotText.clockTime(card.capturedAt) : snapshotText.fullDateTime(card.capturedAt)
        return sameZone ? when : "\(when) · \(snapshotClock.timeZone.abbreviation() ?? card.timeZone)"
    }
    /// Only the caption follows the clock, and only at the midnight that
    /// turns today's time into a date; the app's per-minute `now` redrew
    /// every card each minute.
    private var captureLabel: some View {
        TimelineView(.explicit(captionMidnight)) { _ in
            // Shown as read: a spoken label longer than the visible time
            // read as clipped text to the accessibility audit.
            Text("Captured \(captureText(now: .now))")
                .font(.caption2).foregroundStyle(Palette.textSecondary)
        }
    }
    /// The next midnight for a card captured today; empty for earlier days.
    private var captionMidnight: [Date] {
        let now = Date.now.timeIntervalSince1970 * 1000
        guard app.clock.dayKey(card.capturedAt) == app.clock.dayKey(now) else { return [] }
        return [Date(timeIntervalSince1970: app.clock.addingDays(1, to: app.clock.startOfDay(now)) / 1000 + 1)]
    }
    @ViewBuilder private var refreshButton: some View {
        if card.refreshIntent != nil {
            // One verb on every card: drafts and snapshots both refresh.
            Button { assistant.refresh(card, app: app) } label: {
                Label { Text("Refresh") } icon: { Image(systemName: "arrow.clockwise").accessibilityHidden(true) }
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
        case .capabilities: "questionmark.circle"
        case .repeatDrink: "cup.and.saucer"
        case .welcome: "hand.wave"
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
                let upcoming = CalendarAgenda.briefing(card.commitments, now: Date(timeIntervalSince1970: card.capturedAt / 1000), calendar: .current)
                if card.state != .loading && upcoming.isEmpty { Text("Nothing else on your calendars today.").font(.caption).foregroundStyle(Palette.textSecondary) }
                ForEach(upcoming, id: \.identity) { event in BriefingEventRow(event: event) }
                Button("Review my day") { assistant.send("Review calendar", app: app) }.buttonStyle(.auroraSecondary)
            }
        case .trends: trends
        case .calendar: EmptyView()
        case .reaction:
            metricRows
            Button(card.state == .saved ? "Take another test" : "Start 30-second test") { assistant.historySheet = .reactionTest }
                .buttonStyle(.auroraPrimary).accessibilityIdentifier("assistant-reaction-start")
        case .history: history
        case .exports: exports
        case .energyProjection: projection
        case .energyCheckIn: checkInEditor
        case .cutoffScenario: CutoffScenarioCardView(message: message, card: card, active: draftActive)
        case .reminders: reminders
        case .clarification:
            ForEach([AssistantIntent.logCaffeine, .logSleep, .explainEnergy, .energyProjection, .energyCheckIn, .weeklyTrends, .calendar, .help].compactMap(Capabilities.capability)) { capability in
                capabilityRow(capability)
            }
        case .capabilities:
            ForEach(Capability.Group.allCases.filter { $0 != .help }, id: \.self) { group in
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: group.rawValue)
                    ForEach(Capabilities.all.filter { $0.group == group }) { capabilityRow($0, showsSymbol: true) }
                }
            }
        case .welcome: WelcomeChips()
        case .repeatDrink:
            if card.state == .ready {
                Button("Log it") { assistant.reviewRepeatDrink(message, app: app) }
                    .buttonStyle(.auroraPrimary).disabled(assistant.processing)
                    .accessibilityIdentifier("repeat-drink-review")
                Button("Not today") { assistant.dismissRepeatDrink(message, app: app) }
                    .buttonStyle(.auroraSecondary)
                    .accessibilityIdentifier("repeat-drink-dismiss")
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
    /// Each setting appears once, as its own control, named as in Aurora
    /// settings. A switch that depends on another shows only once that one
    /// is on, nested under it. Aurora settings is the one place for the rest.
    @ViewBuilder private var reminders: some View {
        let prefs = assistant.conversation.preferences
        wakeReminderRow
        DrinkFollowUpControls()
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Toggle("Offer useful updates", isOn: Binding(get: { assistant.conversation.preferences.proactive }, set: { enabled in
                assistant.conversation.preferences.proactive = enabled; assistant.save()
                Task { await assistant.syncBriefingNotification(prompt: enabled); await assistant.syncRepeatDrinkNotifications(app: app) }
            }))
            .accessibilityIdentifier("assistant-proactive")
            if prefs.proactive {
                Toggle("Morning briefing", isOn: Binding(get: { assistant.conversation.preferences.morningBriefing }, set: { enabled in
                    assistant.conversation.preferences.morningBriefing = enabled; assistant.save()
                    Task { await assistant.syncBriefingNotification(prompt: enabled); await assistant.syncRepeatDrinkNotifications(app: app) }
                }))
                .padding(.leading, Metrics.md)
                .accessibilityIdentifier("assistant-morning-briefing")
            } else {
                Text("Morning briefing is available once this is on.").font(.footnote).foregroundStyle(Palette.textSecondary)
            }
        }
        Toggle("Cutoff reminder", isOn: Binding(get: { app.state.prefs.cutoffReminderOn }, set: { enabled in
            Task { await app.setReminder(enabled: enabled) }
        }))
        .disabled(app.state.prefs.cutoffHour == nil)
        if app.state.prefs.cutoffHour == nil {
            Text("Set a cutoff time in Settings first.").font(.footnote).foregroundStyle(Palette.textSecondary)
        }
        if app.reminderStatus == .denied { NotificationsOffNotice() }
        Button("Manage reminders") { assistant.showAssistantSettings = true }
            .buttonStyle(.auroraSecondary).accessibilityIdentifier("assistant-manage-reminders")
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
                EnergyMetricHero(item: item)
            }
            if let outlook = card.energy?.outlook { EnergyOutlookView(outlook: outlook, text: snapshotText) }
            // Missing inputs stay visible, with a way to add them.
            EnergyRecordActions(metrics: card.metrics) { kind in assistant.send(kind == "sleep" ? "Log sleep" : "Log caffeine", app: app) }
            // Everything else only when asked for.
            if card.kind == .energy {
                CardDisclosure(title: "What’s recorded") {
                    ForEach(card.metrics.filter { $0.id != "alertness" }) { EnergyMetricHero(item: $0) }
                }
                if let energy = card.energy {
                    CardDisclosure(title: "What the model used") { EnergyEvidenceSections(snapshot: energy, text: snapshotText) }
                }
            }
            CardDisclosure(title: "What this means") {
                Text(EnergyExplainer.meaning).font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    @ViewBuilder private var projection: some View {
        if let energy = card.energy, let projection = energy.projection, !projection.points.isEmpty {
            if card.state == .failed { Text(card.summary).font(.footnote).foregroundStyle(Palette.destructive) }
            let chart = EnergyTimelineChart(snapshot: energy, projection: projection, text: snapshotText, timeZone: snapshotClock.timeZone)
            chart
            if let outlook = energy.outlook { EnergyOutlookView(outlook: outlook, text: snapshotText) }
            CardDisclosure(title: "What’s recorded in this window") { chart.observations.padding(.top, Metrics.xs) }
            CardDisclosure(title: "What the model used") { EnergyEvidenceSections(snapshot: energy, text: snapshotText) }
            CardDisclosure(title: "What this means") {
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
                DateTimeField(label: "Time", date: Binding(get: { Date(timeIntervalSince1970: (assistant.pendingCheckIn?.recordedAt ?? app.now) / 1000) }, set: { assistant.pendingCheckIn?.recordedAt = $0.timeIntervalSince1970 * 1000 }), id: "assistant-checkin-time")
                if draft.rating != nil, let problem = draft.validate(now: AppModel.currentMillis()).message { fieldProblem(problem) }
                Text(EnergyCheckIn.sourceLabel + " · local time").font(Typography.source).foregroundStyle(Palette.textSecondary)
                noteField(Binding(get: { assistant.pendingCheckIn?.note ?? "" }, set: { assistant.pendingCheckIn?.note = $0 }), id: "assistant-checkin-note")
                draftActions(save: draft.original == nil ? "Save check-in" : "Save correction", saveID: "assistant-checkin-save", disabled: false) { assistant.saveCheckIn(app: app) }
                recentCheckIns
            }
            .transition(Motion.stateTransition(reduceMotion: reduceMotion))
        } else {
            closedDraft(card.state == .saved ? "Saved. See the receipt below." : "This check-in is closed. Refresh to record a rating.")
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
                    quietButton("Edit check-in") { assistant.editCheckIn(message, app: app) }
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
                        Label { Text("\(preset.label) · \(numberText(preset.mg)) mg") } icon: { Image(systemName: preset.symbol).accessibilityHidden(true) }
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
        // Scrolls edge to edge inside the card, clipped at its border, while
        // the first chip still lines up with the card's other content.
        .contentMargins(.horizontal, Metrics.md, for: .scrollContent)
        .padding(.horizontal, -Metrics.md)
    }
    @ViewBuilder private var caffeineEditor: some View {
        if draftActive, let draft = assistant.pendingDraft {
            VStack(alignment: .leading, spacing: Metrics.md) {
                drinkChips(selected: draft)
                LabeledField(label: "Amount", unit: "mg", isFocused: field == .amount) {
                    TextField("Enter amount", text: Binding(get: { assistant.pendingDraft?.mg ?? "" }, set: { assistant.pendingDraft?.mg = $0 }))
                        .keyboardType(.numberPad).font(Typography.evidence).monospacedDigit().focused($field, equals: .amount)
                        .accessibilityLabel("Amount, milligrams")
                        .accessibilityIdentifier("assistant-dose-amount")
                }
                // Mirrors Save's own validation once something is typed; Save
                // stays enabled and still reports an empty amount itself.
                if !draft.mg.isEmpty, let problem = CaffeineLog.validate(draft, now: AppModel.currentMillis()).message {
                    fieldProblem(problem)
                }
                LabeledField(label: "Drink or source", isFocused: field == .source) {
                    TextField("Drink or source", text: Binding(get: { assistant.pendingDraft?.source ?? "" }, set: { assistant.pendingDraft?.source = $0 }))
                        .font(Typography.evidence).focused($field, equals: .source)
                        .accessibilityLabel("Drink or source")
                        .accessibilityIdentifier("assistant-dose-source")
                }
                DateTimeField(label: "Recorded time", date: Binding(get: { Date(timeIntervalSince1970: (assistant.pendingDraft?.timestamp ?? app.now) / 1000) }, set: { assistant.pendingDraft?.timestamp = $0.timeIntervalSince1970 * 1000 }), id: "assistant-dose-time")
                Text("Manual · local time").font(Typography.source).foregroundStyle(Palette.textSecondary)
                draftActions(save: "Save caffeine", saveID: "assistant-dose-save", disabled: false) { assistant.saveDose(app: app) }
            }
            .transition(Motion.stateTransition(reduceMotion: reduceMotion))
        } else { closedDraft(card.state == .saved ? "Saved. See the receipt below." : "This draft is closed. Refresh to record an entry.") }
    }
    private func fieldProblem(_ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: StatusTone.error.symbol).accessibilityHidden(true) }
            .font(.footnote).foregroundStyle(Palette.destructive)
    }
    /// An optional note, named once for VoiceOver.
    private func noteField(_ text: Binding<String>, id: String) -> some View {
        LabeledField(label: "Note", isFocused: field == .note) {
            TextField("Optional note", text: text)
                .font(Typography.evidence).focused($field, equals: .note)
                .accessibilityLabel("Note").accessibilityIdentifier(id)
        }
    }
    /// A full-width quiet action: the whole 44 pt row is the target, not
    /// just its text.
    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.auroraPress)
        .foregroundStyle(Palette.tint)
    }
    /// Save leads; Discard is the quiet way out. Stacked so both keep a full
    /// touch target at every text size.
    private func draftActions(save: String, saveID: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: Metrics.xxs) {
            Button(save, action: action).buttonStyle(.auroraPrimary).accessibilityIdentifier(saveID).disabled(disabled)
            quietButton("Discard") { assistant.discardDraft() }
                .accessibilityIdentifier("assistant-discard")
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
        if draftActive, let entry = assistant.pendingSleep {
            VStack(alignment: .leading, spacing: Metrics.md) {
                sleepTime("Start", key: \.start, id: "start")
                sleepTime("End", key: \.end, id: "end")
                // Duration and problems only once both times are the person's.
                if let draft = entry.draft {
                    valueRow("Duration", formatHoursMinutes(durationMs: max(0, draft.end - draft.start)))
                        .accessibilityElement(children: .combine)
                    if let problem = entry.validate(now: AppModel.currentMillis()).message { fieldProblem(problem) }
                }
                Text("Manual · local time").font(Typography.source).foregroundStyle(Palette.textSecondary)
                noteField(Binding(get: { assistant.pendingSleep?.note ?? "" }, set: { assistant.pendingSleep?.note = $0 }), id: "assistant-sleep-note")
                draftActions(save: "Save sleep", saveID: "assistant-sleep-save", disabled: entry.validate(now: AppModel.currentMillis()) != .valid) { assistant.saveSleep(app: app) }
            }
            .transition(Motion.stateTransition(reduceMotion: reduceMotion))
        } else { closedDraft(card.state == .saved ? "Saved. See the receipt below." : "This draft is closed. Refresh to record sleep.") }
    }
    /// A sleep time once the person has added it; until then, a button that
    /// adds it at the current minute, a neutral starting point to change,
    /// never a proposed bedtime or wake time.
    @ViewBuilder private func sleepTime(_ label: String, key: WritableKeyPath<ManualSleep.Entry, Millis?>, id: String) -> some View {
        if assistant.pendingSleep?[keyPath: key] != nil {
            DateTimeField(label: label, date: sleepDate(key), id: "assistant-sleep-\(id)")
        } else {
            Button("Add \(label.lowercased())") { assistant.pendingSleep?[keyPath: key] = ManualSleep.addedTime(now: AppModel.currentMillis()) }
                .buttonStyle(.auroraSecondary).accessibilityIdentifier("assistant-sleep-add-\(id)")
        }
    }
    private func sleepDate(_ key: WritableKeyPath<ManualSleep.Entry, Millis?>) -> Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: (assistant.pendingSleep?[keyPath: key] ?? app.now) / 1000) }, set: { assistant.pendingSleep?[keyPath: key] = $0.timeIntervalSince1970 * 1000 })
    }
    @ViewBuilder private var trends: some View {
        Picker("Recorded signal", selection: $metric) { ForEach(["Caffeine", "Sleep", "Reaction"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("assistant-trend-metric")
        Picker("Range", selection: $days) { Text("Week").tag(7); Text("Month").tag(30) }.pickerStyle(.segmented).accessibilityIdentifier("assistant-trend-range")
        if let series = card.series.first(where: { $0.metric == metric && $0.days == days }) {
            DailyBarChart(title: metric == "Caffeine" && days == 7 ? "Recorded caffeine · this week" : "Recorded \(metric.lowercased()) · \(days) days", days: series.points.map {
                .init(date: $0.date, value: $0.value, title: snapshotText.weekdayDate($0.date), readout: $0.detail, isSample: $0.sample)
            }, unit: series.unit, accent: metric == "Caffeine" ? Palette.caffeineAccent : Palette.tint, accessibilitySummary: series.summary, emptyMessage: "No \(metric.lowercased()) recorded in this range.", framed: false).environment(\.timeZone, snapshotClock.timeZone)
            Text(series.comparison).font(.footnote).foregroundStyle(Palette.textSecondary)
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            LabeledField(label: "Search", isFocused: field == .search) {
                TextField("Search records", text: $query)
                    .font(Typography.evidence).focused($field, equals: .search)
                    .accessibilityLabel("Search history").accessibilityIdentifier("assistant-history-search")
            }
            Picker("Date range", selection: $historyDays) {
                Text("7d").accessibilityLabel("7 days").tag(7)
                Text("30d").accessibilityLabel("30 days").tag(30)
                Text("All").tag(0)
            }
            .pickerStyle(.segmented)
            Picker("Source", selection: $source) { ForEach(["All sources", "Manual", "Health", "Sample Data", "Recorded"], id: \.self) { Text($0).tag($0) } }
            // Filtered once per body; it scans every record in the snapshot.
            let records = filteredRecords
            let shown = records.prefix(historyLimit)
            let samples = shown.filter(\.isSample)
            if records.isEmpty { Text("No matching records in this snapshot.").foregroundStyle(Palette.textSecondary) }
            ForEach(shown.filter { !$0.isSample }, id: \.identity) { historyRow($0) }
            // Sample Data is labeled once, above its own rows.
            if !samples.isEmpty {
                SampleDataBadge().padding(.top, Metrics.xs)
                ForEach(samples, id: \.identity) { historyRow($0) }
            }
            if records.count > historyLimit { Button("Show more records (\(records.count) total)") { historyLimit += 30 }.frame(minHeight: Metrics.minimumTouchTarget) }
        }
    }
    private func historyRow(_ row: AssistantCard.Record) -> some View {
        // A sample row's source is the section's badge.
        let source = row.isSample ? [] : [row.source]
        let detail = ([snapshotText.weekdayDate(row.date)] + source + [row.editable ? "Edit" : "Read-only"]).joined(separator: " · ")
        return Button { edit(row) } label: {
            HStack(spacing: Metrics.sm) {
                VStack(alignment: .leading, spacing: Metrics.xxs) {
                    Text(row.title + " · " + row.detail).font(.subheadline.weight(.medium)).monospacedDigit()
                    Text(detail).font(Typography.source).foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
                if row.editable { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.textTertiary).accessibilityHidden(true) }
            }.frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.auroraPress).disabled(!row.editable)
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
    /// Each file is built only when shared, not on every redraw. The daily
    /// totals end at the moment of sharing, so they don't read the app's
    /// per-minute `now` either.
    private var exports: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            ShareLink(item: CSVFile(name: "aurora-caffeine-entries.csv") { [doses = app.state.doses, clock = app.clock] in
                Export.doseEntriesCSV(doses, clock: clock)
            }, preview: SharePreview("Caffeine entries")) { Label("Caffeine entries CSV", systemImage: "cup.and.saucer") }
            ShareLink(item: CSVFile(name: "aurora-sleep.csv") { [sleeps = app.state.sleeps, clock = app.clock] in
                Export.sleepSessionsCSV(sleeps, clock: clock)
            }, preview: SharePreview("Sleep records")) { Label("Sleep records CSV", systemImage: "moon") }
            ShareLink(item: CSVFile(name: "aurora-reaction-tests.csv") { [sessions = app.state.vigilanceSessions] in
                Export.vigilanceSessionsCSV(sessions)
            }, preview: SharePreview("Reaction tests")) { Label("Reaction tests CSV", systemImage: "hand.tap") }
            ShareLink(item: CSVFile(name: "aurora-energy-check-ins.csv") { [checkIns = app.state.energyCheckIns, clock = app.clock] in
                Export.energyCheckInsCSV(checkIns, clock: clock)
            }, preview: SharePreview("Energy check-ins")) { Label("Energy check-ins CSV", systemImage: "hand.raised") }
            ShareLink(item: CSVFile(name: "aurora-daily-caffeine.csv") { [doses = app.state.doses, clock = app.clock] in
                Export.dailyTotalsCSV(Export.dailyTotalRows(doses, now: (Date.now.timeIntervalSince1970 * 1000).rounded(), clock: clock))
            }, preview: SharePreview("Daily caffeine totals")) { Label("Daily caffeine totals CSV", systemImage: "chart.bar") }
        }.buttonStyle(.auroraSecondary)
    }
    @ViewBuilder private var calendar: some View {
        if card.state == .loading {
            Card { Label(card.title, systemImage: "calendar").font(.headline); ProgressView("Reading selected commitments…"); Text("No changes have been made.").font(.caption) }
        } else {
            CalendarReviewCard(service: assistant.calendars, snapshot: card.commitments, editable: active, snapshotMessage: card.state == .failed ? card.summary : nil, capturedAt: Date(timeIntervalSince1970: card.capturedAt / 1000), onOutcome: { text, updated in
                var receipt = AssistantCard(kind: .receipt, capturedAt: app.now, title: updated == nil ? "Calendar change not confirmed" : "Calendar updated", summary: text)
                receipt.state = updated == nil ? .failed : .saved
                if let updated { receipt.commitments = [updated] }
                assistant.appendCard(receipt)
            }) { assistant.showCalendarSettings = true }
        }
    }
}

/// A disclosure inside a card whose whole title row is a 44 pt target.
struct CardDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        DisclosureGroup {
            content()
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
    }
}

/// A draft's date and time: the label above, then the date and time chips
/// from the card's leading edge, so every row's chips line up. At
/// accessibility sizes each chip gets its own row instead of squeezing the
/// label. VoiceOver hears each picker's own name once ("Start, date").
private struct DateTimeField: View {
    let label: String
    @Binding var date: Date
    let id: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(label).font(Typography.label).foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.xs))
                : AnyLayout(HStackLayout(spacing: Metrics.xs))
            layout {
                DatePicker("\(label), date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    .labelsHidden().frame(minHeight: Metrics.minimumTouchTarget)
                    .accessibilityIdentifier("\(id)-date")
                DatePicker("\(label), time", selection: $date, in: ...Date.now, displayedComponents: .hourAndMinute)
                    .labelsHidden().frame(minHeight: Metrics.minimumTouchTarget)
                    .accessibilityIdentifier("\(id)-time")
            }
        }
    }
}

private extension AssistantCard.Record {
    var isSample: Bool { source == "Sample Data" }
}

enum EnergyCardTiming {
    /// An energy snapshot older than this is labeled as earlier. Its
    /// results never change; Refresh captures a new one.
    static let staleAfterMs: Millis = hourMs
}

/// One upcoming event in the briefing: its time, then its title, marked by
/// its calendar's color.
private struct BriefingEventRow: View {
    let event: Commitment

    private var time: String {
        event.allDay == true ? "All day" : event.start.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
            Circle().fill(Color(calendarHex: event.colorHex) ?? Palette.tint).frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(time).font(.subheadline.monospacedDigit()).foregroundStyle(Palette.textSecondary)
            Text(event.title).font(.subheadline).foregroundStyle(Palette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
