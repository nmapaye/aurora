import AuroraCore
import Foundation

/// A reminder preview for one calculated scenario. Save revalidates it
/// against current records, settings, zone and time first.
struct CutoffReminderPreview: Equatable {
    let messageID: UUID
    let snapshot: CutoffScenario.Snapshot
    let content: CutoffScenario.ReminderContent
}

/// Cutoff scenarios: editing changes only the open inputs. Calculate freezes
/// a result on the card; nothing is recorded, and a notification is written
/// only by an explicit Save of a current preview.
extension AssistantModel {
    func openCutoff(input: CutoffScenario.Input = .init(), app: AppModel) {
        expireDraft()
        pendingCutoff = input
        pendingMessageID = appendCard(AssistantCards.cutoffScenario(input: input, state: app.state, now: app.now, clock: app.clock, text: app.text), intent: .cutoffScenario)
    }

    /// Refresh is a new snapshot with the earlier inputs, calculated from
    /// current records. The earlier card keeps its result.
    func refreshCutoff(_ card: AssistantCard, app: AppModel) {
        app.tick()
        openCutoff(input: card.cutoff?.input ?? .init(), app: app)
    }

    /// The open scenario card, if `id` is it and it can still act.
    private func openCutoffCard(_ id: UUID?) -> AssistantCard? {
        guard let id, id == pendingMessageID, pendingCutoff != nil, activeCards.contains(id),
              let card = conversation.messages.first(where: { $0.id == id })?.card,
              card.kind == .cutoffScenario, card.state == .ready else { return nil }
        return card
    }

    /// Any edit makes an open preview stale.
    func editCutoff(_ change: (inout CutoffScenario.Input) -> Void) {
        guard pendingCutoff != nil else { return }
        change(&pendingCutoff!)
        cutoffPreview = nil
    }

    func calculateCutoff(app: AppModel) {
        guard let id = pendingMessageID, let card = openCutoffCard(id), let input = pendingCutoff else { return }
        app.tick()
        guard card.timeZone == app.clock.timeZone.identifier else {
            failure = "Your time zone changed. Start a new scenario."
            expireDraft(); return
        }
        failure = nil; cutoffPreview = nil
        let snapshot = CutoffScenario.evaluate(input: input, doses: app.state.doses, halfLifeHours: app.state.prefs.halfLife, now: app.now, timeZone: app.clock.timeZone)
        updateCard(id) { $0.cutoff = snapshot }
    }

    private func revalidate(_ snapshot: CutoffScenario.Snapshot, input: CutoffScenario.Input, app: AppModel) -> CutoffScenario.Revalidation {
        CutoffScenario.revalidate(snapshot, input: input, doses: app.state.doses, halfLifeHours: app.state.prefs.halfLife, now: app.now, timeZone: app.clock.timeZone, text: app.text)
    }

    func previewCutoffReminder(app: AppModel) {
        guard let id = pendingMessageID, let snapshot = openCutoffCard(id)?.cutoff, let input = pendingCutoff, !savingCutoffReminder else { return }
        app.tick()
        switch revalidate(snapshot, input: input, app: app) {
        case .current(let content):
            failure = nil
            cutoffPreview = .init(messageID: id, snapshot: snapshot, content: content)
        case .changed(let reason):
            cutoffPreview = nil; failure = reason
            updateCard(id) { $0.cutoff?.reminder = .needsNewPreview }
        }
    }

    /// Schedules the previewed reminder after checking it is still current.
    /// Repeated taps while saving, or after the preview closed, do nothing.
    func saveCutoffReminder(app: AppModel) async {
        guard let preview = cutoffPreview, !savingCutoffReminder, openCutoffCard(preview.messageID) != nil, let input = pendingCutoff else { return }
        savingCutoffReminder = true
        defer { savingCutoffReminder = false }
        app.tick()
        guard case .current(let content) = revalidate(preview.snapshot, input: input, app: app), content == preview.content else {
            cutoffPreview = nil
            failure = "Something changed since the preview. Calculate and preview again. Nothing was scheduled."
            updateCard(preview.messageID) { $0.cutoff?.reminder = .needsNewPreview }
            return
        }
        let outcome = await (scheduleCutoffReminder ?? { await app.reminders.scheduleScenario($0) })(content)
        // Cleared or erased meanwhile: there is no conversation to report into.
        guard conversation.messages.contains(where: { $0.id == preview.messageID }) else { return }
        app.tick()
        switch outcome {
        case .scheduled:
            failure = nil
            if cutoffPreview == preview { cutoffPreview = nil }
            updateCard(preview.messageID) { $0.cutoff?.reminder = .scheduled(fireAt: content.fireAt, savedAt: app.now) }
            var receipt = AssistantCard(kind: .receipt, capturedAt: app.now, title: "Scenario reminder scheduled")
            receipt.state = .saved
            receipt.timeZone = app.clock.timeZone.identifier
            receipt.summary = "One reminder on this device. Your daily cutoff reminder is unchanged. A user-defined scenario, not a safety limit."
            receipt.metrics = [.init(id: "reminder", label: "Reminder", value: app.text.fullDateTime(content.fireAt), source: preview.snapshot.timeZone)]
            appendCard(receipt)
        case .notAllowed:
            failure = "Notifications aren’t allowed for Aurora, so nothing was scheduled. You can allow them in iOS Settings, then save again."
            updateCard(preview.messageID) { $0.cutoff?.reminder = .notAllowed }
        case .failed:
            failure = "The reminder couldn’t be scheduled. Nothing was saved."
            updateCard(preview.messageID) { $0.cutoff?.reminder = .failed }
        }
    }

    func cancelCutoffPreview() { cutoffPreview = nil }
}
