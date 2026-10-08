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

    private var snapshotClock: LocalClock { LocalClock(timeZone: TimeZone(identifier: card.timeZone) ?? .current) }
    private var snapshotText: DateText { .localized(timeZone: snapshotClock.timeZone) }
    private var active: Bool { assistant.activeCards.contains(message.id) && card.state == .ready }
    private var draftActive: Bool { active && assistant.pendingMessageID == message.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if card.kind == .calendar {
                calendar
            } else {
                Card {
                    Label(card.title, systemImage: symbol).font(.headline).accessibilityAddTraits(.isHeader).accessibilityIdentifier("assistant-card-\(card.kind.rawValue)")
                    if !card.summary.isEmpty && card.kind != .energy && card.kind != .briefing {
                        Text(card.summary).font(.subheadline).foregroundStyle(Palette.textSecondary)
                    }
                    content
                }
            }
            if card.kind != .clarification {
                ViewThatFits(in: .horizontal) {
                    HStack { captureLabel; Spacer(); refreshButton }
                    VStack(alignment: .leading, spacing: 8) { captureLabel; refreshButton }
                }
            }
        }
        .sheet(item: $editingDose) { mode in
            if case .edit(let original) = mode {
                DoseEntrySheet(mode: mode, draft: CaffeineLog.editDraft(for: original)) { result in
                    guard app.state.doses.first(where: { $0.id == original.id }) == original else { assistant.failure = "This record changed. Refresh history before editing."; return }
                    switch result {
                    case .saved(let draft):
                        app.correctDose(id: original.id, with: draft)
                        if app.mutationFailure == nil { assistant.receipt(recordID: original.id, kind: "caffeine", app: app, title: "Caffeine updated") }
                        else { assistant.failure = app.mutationFailure }
                    case .deleted:
                        app.deleteDose(id: original.id)
                        if app.mutationFailure == nil { assistant.append("Caffeine entry deleted.") }
                        else { assistant.failure = app.mutationFailure }
                    case .cancelled: break
                    }
                }
            }
        }
        .sheet(item: $editingSleep) { mode in
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
    }
    private var captureLabel: some View {
        Text("Captured \(snapshotText.fullDateTime(card.capturedAt)) · \(card.timeZone)")
            .font(.caption2).foregroundStyle(Palette.textSecondary)
    }
    @ViewBuilder private var refreshButton: some View {
        if card.refreshIntent != nil {
            Button(card.kind == .caffeineDraft || card.kind == .sleepDraft || card.kind == .calendar ? "New review" : "Refresh") {
                assistant.refresh(card, app: app)
            }.font(.caption.weight(.medium)).frame(minHeight: 44)
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
        case .reminders:
            metricRows
            Text("Current device controls").font(.caption.weight(.medium)).foregroundStyle(Palette.textSecondary)
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
            ForEach([("Record caffeine", "Log caffeine"), ("Record sleep", "Log sleep"), ("Understand my energy", "How is my energy?"), ("Explore trends", "Show this week"), ("Review my day", "Review calendar")], id: \.0) { label, prompt in
                Button { assistant.send(prompt, app: app) } label: { HStack { Text(label); Spacer(); Image(systemName: "chevron.right") }.frame(minHeight: 44) }
                    .buttonStyle(.plain).foregroundStyle(Palette.tint).disabled(assistant.processing)
            }
        case .receipt:
            ForEach(card.records, id: \.identity) { row in
                Text(row.title + " · " + row.detail).font(.subheadline)
                Text(row.source + " · " + Date(timeIntervalSince1970: row.date / 1000).formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Palette.textSecondary)
            }
            metricRows
            if card.state == .saved && card.recordID != nil && !card.title.lowercased().contains("updated") {
                Button("Undo entry") { assistant.undoReceipt(message, app: app) }.buttonStyle(.auroraSecondary).accessibilityIdentifier("assistant-undo")
            }
        }
    }
    private var metricRows: some View {
        ForEach(card.metrics) { item in
            VStack(alignment: .leading, spacing: 4) {
                Text(item.label).font(.subheadline).foregroundStyle(Palette.textSecondary)
                Text(item.value).font(.title3.weight(.semibold)).monospacedDigit()
                Text(item.source).font(.caption).foregroundStyle(Palette.textSecondary)
                if !item.detail.isEmpty { Text(item.detail).font(.footnote).foregroundStyle(Palette.textSecondary) }
            }.padding(.vertical, 4).accessibilityElement(children: .combine)
        }
    }
    private var evidence: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(card.metrics) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.label).font(.subheadline).foregroundStyle(Palette.textSecondary)
                    Text(item.value).font(.title2.weight(.semibold)).monospacedDigit()
                    if !item.source.isEmpty { Text(item.source).font(.caption).foregroundStyle(Palette.textSecondary) }
                    if item.missing && item.id != "alertness" {
                        Button(item.id == "sleep" ? "Record sleep" : "Record caffeine") { assistant.send(item.id == "sleep" ? "Log sleep" : "Log caffeine", app: app) }.font(.subheadline).frame(minHeight: 44)
                    }
                }.accessibilityElement(children: .contain)
            }
            DisclosureGroup("What this means") {
                if let estimate = card.metrics.first(where: { $0.id == "alertness" }) { Text(estimate.detail).font(.footnote) }
                Text(card.summary).font(.footnote).padding(.top, 4)
            }
            DisclosureGroup("What’s missing") {
                if card.metrics.contains(where: \.missing) { Text("Missing records stay ‘No record’. You can add an entry above; Aurora will not fill in a cause or a measurement.").font(.footnote) }
                else { Text("Stress, illness, and other factors aren't measured here. Recorded signals cannot establish a cause.").font(.footnote) }
            }
        }
    }
    @ViewBuilder private var caffeineEditor: some View {
        if draftActive, assistant.pendingDraft != nil {
            TextField("Amount in mg", text: Binding(get: { assistant.pendingDraft?.mg ?? "" }, set: { assistant.pendingDraft?.mg = $0 }))
                .keyboardType(.numberPad).padding(12).frame(minHeight: 44).background(Palette.cardMuted, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("assistant-dose-amount")
            TextField("Drink or source", text: Binding(get: { assistant.pendingDraft?.source ?? "" }, set: { assistant.pendingDraft?.source = $0 }))
                .padding(12).frame(minHeight: 44).background(Palette.cardMuted, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("assistant-dose-source")
            DatePicker("Recorded time", selection: Binding(get: { Date(timeIntervalSince1970: (assistant.pendingDraft?.timestamp ?? app.now) / 1000) }, set: { assistant.pendingDraft?.timestamp = $0.timeIntervalSince1970 * 1000 }), in: ...Date.now)
            Button("Save entry") { assistant.saveDose(app: app) }.buttonStyle(.auroraPrimary).accessibilityIdentifier("assistant-dose-save")
            Button("Discard") { assistant.discardDraft() }.frame(minHeight: 44)
        } else { metricRows; Text(card.state == .saved ? "Saved. See the receipt below." : "This draft is closed. Start a new review to record an entry.").font(.footnote).foregroundStyle(Palette.textSecondary) }
    }
    @ViewBuilder private var sleepEditor: some View {
        if draftActive, let draft = assistant.pendingSleep {
            DatePicker("Start", selection: sleepDate(\.start), in: ...Date.now).accessibilityIdentifier("assistant-sleep-start")
            DatePicker("End", selection: sleepDate(\.end), in: ...Date.now).accessibilityIdentifier("assistant-sleep-end")
            Text("Duration · \(formatHoursMinutes(durationMs: max(0, draft.end - draft.start)))").font(.subheadline).monospacedDigit()
            Text("Manual · local time").font(.caption).foregroundStyle(Palette.textSecondary)
            TextField("Optional note", text: Binding(get: { assistant.pendingSleep?.note ?? "" }, set: { assistant.pendingSleep?.note = $0 }))
            if let problem = ManualSleep.validate(start: draft.start, end: draft.end, now: AppModel.currentMillis()).message { Text(problem).font(.footnote).foregroundStyle(Palette.destructive) }
            Button("Save sleep") { assistant.saveSleep(app: app) }.buttonStyle(.auroraPrimary).accessibilityIdentifier("assistant-sleep-save")
                .disabled(ManualSleep.validate(start: draft.start, end: draft.end, now: AppModel.currentMillis()) != .valid)
            Button("Discard") { assistant.discardDraft() }.frame(minHeight: 44)
        } else { metricRows; Text(card.state == .saved ? "Saved. See the receipt below." : "This draft is closed. Start a new review to record sleep.").font(.footnote).foregroundStyle(Palette.textSecondary) }
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
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search records", text: $query).textFieldStyle(.roundedBorder).accessibilityIdentifier("assistant-history-search")
            Picker("Date range", selection: $historyDays) { Text("7d").tag(7); Text("30d").tag(30); Text("All").tag(0) }.pickerStyle(.segmented)
            Picker("Source", selection: $source) { ForEach(["All sources", "Manual", "Health", "Sample Data", "Recorded"], id: \.self) { Text($0).tag($0) } }
            if filteredRecords.isEmpty { Text("No matching records in this snapshot.").foregroundStyle(Palette.textSecondary) }
            ForEach(Array(filteredRecords.prefix(historyLimit)), id: \.identity) { row in
                Button { edit(row) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title + " · " + row.detail).font(.subheadline.weight(.medium))
                        Text(snapshotText.weekdayDate(row.date) + " · " + row.source + (row.editable ? " · Edit" : " · Read-only")).font(.caption).foregroundStyle(Palette.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }.buttonStyle(.plain).disabled(!row.editable)
            }
            if filteredRecords.count > historyLimit { Button("Show more records (\(filteredRecords.count) total)") { historyLimit += 30 }.frame(minHeight: 44) }
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
        VStack(alignment: .leading, spacing: 12) {
            ShareLink(item: CSVFile(name: "aurora-caffeine-entries.csv", text: Export.doseEntriesCSV(app.state.doses, clock: app.clock)), preview: SharePreview("Caffeine entries")) { Label("Caffeine entries CSV", systemImage: "cup.and.saucer") }
            ShareLink(item: CSVFile(name: "aurora-sleep.csv", text: Export.sleepSessionsCSV(app.state.sleeps, clock: app.clock)), preview: SharePreview("Sleep records")) { Label("Sleep records CSV", systemImage: "moon") }
            ShareLink(item: CSVFile(name: "aurora-reaction-tests.csv", text: Export.vigilanceSessionsCSV(app.state.vigilanceSessions)), preview: SharePreview("Reaction tests")) { Label("Reaction tests CSV", systemImage: "hand.tap") }
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
