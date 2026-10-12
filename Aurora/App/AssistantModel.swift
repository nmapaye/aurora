import AuroraCore
import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class AssistantModel {
    var conversation = ConversationState()
    var processing = false
    var status = ""
    var failure: String?
    var pendingDraft: CustomDoseDraft?
    var pendingMessageID: UUID?
    var pendingSleep: ManualSleep.Draft?
    /// An open check-in review. Its id is fixed when the review opens.
    var pendingCheckIn: EnergyCheckInDraft?
    /// An open cutoff scenario's inputs, apart from its card's frozen result.
    var pendingCutoff: CutoffScenario.Input?
    /// A scenario reminder shown for review; nothing is scheduled until Save.
    var cutoffPreview: CutoffReminderPreview?
    /// The scenario reminder Save in flight. Closing or replacing the
    /// scenario clears it, so a late result can't act on newer state.
    var cutoffSaveOperation: UUID?
    /// Tests and the Design Gallery replace this; nil uses the app's ReminderService.
    /// Production follows the system zone as it changes; tests pin it.
    @ObservationIgnored var cutoffZone: () -> TimeZone = { TimeZone(identifier: TimeZone.autoupdatingCurrent.identifier) ?? .current }
    @ObservationIgnored var scheduleCutoffReminder: (@MainActor (CutoffScenario.ReminderContent) async -> ReminderService.ScenarioOutcome)?
    var activeCards: Set<UUID> = []
    var savedDose: Dose?
    var showSleepEntry = false
    var showCalendarSettings = false
    var showAssistantSettings = false
    var historySheet: AssistantIntent?
    /// Messages whose card has a text field with keyboard focus. Each card
    /// releases only its own entry, so a card losing focus after another
    /// gained it can't clear the other's. Interaction state, never saved.
    private(set) var focusedCards: Set<UUID> = []
    /// While true the composer inset keeps only its field, so the card's
    /// Save stays above the keyboard.
    var editingCardField: Bool { !focusedCards.isEmpty }

    func cardFocus(_ message: UUID, focused: Bool) {
        if focused { focusedCards.insert(message) } else { focusedCards.remove(message) }
    }

    func clearCardFocus() { focusedCards = [] }
    let calendars: CalendarService
    private let makeConversationStore: () throws -> ConversationStore
    private var store: ConversationStore?
    private var task: Task<Void, Never>?
    private var started = false
    private var requestID: UUID?
    private var storageReady = false
    private let appleModel = AppleIntentModel()
    private var intentCache = IntentCache()
    private var cacheGeneration = 0

    init(calendars: CalendarService? = nil, makeStore: @escaping () throws -> ConversationStore = {
        ConversationStore(directory: try StateStore.live().directory)
    }) {
        // Created with the App, before the first frame: EventKit store and
        // the Google credential lookup run synchronously here.
        self.calendars = calendars ?? Signposts.measure("Launch.CalendarServiceInit") { CalendarService() }
        self.makeConversationStore = makeStore
        #if DEBUG
        scheduleCutoffReminder = Self.uiTestCutoffScheduler()
        #endif
    }

    var intelligenceName: String {
        if conversation.preferences.useMacModel { return "Mac local · \(conversation.preferences.macModel)" }
        // Read while the conversation's first frame renders.
        let available = Signposts.measure("Assistant.ModelAvailability") { AppleIntentModel.available }
        return available ? "On-device intelligence" : "Local quick actions · AI unavailable"
    }

    func start(app: AppModel) async {
        guard !started else { return }
        started = true
        let interval = Signposts.signposter.beginInterval("Assistant.Start")
        defer { Signposts.signposter.endInterval("Assistant.Start", interval) }
        do {
            let store = try makeConversationStore()
            self.store = store
            conversation = try Signposts.measure("Assistant.ConversationLoad") {
                ProcessInfo.processInfo.arguments.contains("-AuroraUITestReset") ? ConversationState() : try store.load()
            }
            storageReady = true
            for index in conversation.messages.indices {
                if let card = conversation.messages[index].card {
                    if card.state == .loading {
                        conversation.messages[index].card?.state = .failed
                        conversation.messages[index].card?.summary = "This request didn't finish. Refresh for a current result."
                    } else if [.caffeineDraft, .sleepDraft, .calendar, .energyCheckIn, .cutoffScenario].contains(card.kind), card.state == .ready {
                        conversation.messages[index].card?.state = .expired
                    }
                }
            }
            if conversation.messages.isEmpty {
                appendCard(AssistantCards.make(.clarification, state: app.state, now: app.now, clock: app.clock, text: app.text))
            }
            if app.state.isWalkthroughPending { app.completeWalkthrough() }
            await Signposts.measureAsync("Assistant.CalendarListRefresh") { await calendars.refreshCalendars() }
            await foreground(app: app)
        } catch {
            Signposts.lifecycle.error("conversation storage did not open")
            failure = "Your conversation couldn't be opened. It has been preserved. Records and native tools remain available."
        }
    }

    func prepareForInput() {
        guard !processing, !conversation.preferences.useMacModel else { return }
        // Runs as the keyboard appears; times the synchronous part only.
        Signposts.measure("Assistant.Prewarm") { appleModel.prewarm() }
    }

    func releaseWarmResources() {
        appleModel.releasePreparedSession()
        intentCache.clear()
        cacheGeneration += 1
    }

    func clearConversation() {
        task?.cancel(); task = nil; requestID = nil; processing = false; status = ""
        var cleared = conversation; cleared.messages = []
        do { try store?.save(cleared) }
        catch { failure = "Couldn't clear the saved conversation. It has been preserved. Please retry."; return }
        conversation = cleared; pendingDraft = nil; pendingSleep = nil; pendingCheckIn = nil
        closeCutoff()
        pendingMessageID = nil; activeCards = []; savedDose = nil
        releaseWarmResources()
        do { try store?.removeMigrationSource() }
        catch { failure = "The conversation was cleared, but its migration source couldn't be removed. Please retry." }
    }

    func resetAfterErase() {
        task?.cancel(); task = nil; requestID = nil; processing = false; status = ""
        conversation = ConversationState(); pendingDraft = nil; pendingSleep = nil; pendingCheckIn = nil
        closeCutoff()
        pendingMessageID = nil; activeCards = []; savedDose = nil; historySheet = nil
        showSleepEntry = false; showCalendarSettings = false; showAssistantSettings = false; clearCardFocus()
        releaseWarmResources(); calendars.resetAfterErase()
        failure = nil
    }

    func save() {
        guard storageReady else { return }
        do { try store?.save(conversation) }
        catch { failure = "Couldn't save the conversation. Your records have not been deleted. Please retry." }
    }
    func append(_ text: String, intent: AssistantIntent? = nil, user: Bool = false) {
        conversation.messages.append(.init(text: text, isUser: user, intent: intent))
        // Keep model prompts independent of transcript size; history remains local.
        save()
    }
    func send(_ input: String, app: AppModel) {
        let text = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !text.isEmpty, !processing else { return }
        append(text, user: true)
        if let draft = pendingDraft, let corrected = AssistantPlanner.correctedDraft(draft, input: text, now: app.now, clock: app.clock),
           !text.lowercased().contains("i had"), !text.lowercased().contains("i drank") {
            pendingDraft = corrected
            updateCard(pendingMessageID) { $0.summary = "Updated proposal · review before saving." }
            return
        }
        if pendingCheckIn != nil, let correction = AssistantPlanner.checkInCorrection(text) {
            switch correction {
            case .rating(let rating):
                pendingCheckIn?.rating = rating
                updateCard(pendingMessageID) { $0.summary = "Updated rating · review before saving." }
            case .outOfScale:
                updateCard(pendingMessageID) { $0.summary = "Ratings run from 1 to 5. Nothing changed." }
            }
            return
        }
        processing = true; status = "Understanding your request"; failure = nil
        let id = UUID(); requestID = id
        let generation = cacheGeneration
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.requestID == id { self.processing = false; self.status = ""; self.task = nil }
            }
            do {
                // Route words only; the request text is never recorded.
                var route = "explicit"
                let classifying = Signposts.signposter.beginInterval("Assistant.Classify")
                var classified = false
                // Also ends the interval on failure or Stop.
                defer { if !classified { Signposts.signposter.endInterval("Assistant.Classify", classifying, "\(route, privacy: .public) ended") } }
                var intent = AssistantPlanner.explicitIntent(text)
                if intent == nil {
                    let source = self.conversation.preferences.useMacModel
                        ? "mac:\(self.conversation.preferences.macModel)" : "apple"
                    if let cached = self.intentCache.lookup(text, model: source) {
                        self.status = "Checking your request"
                        route = "cached"
                        intent = cached
                    } else if self.conversation.preferences.useMacModel {
                        self.status = "Asking your Mac’s local model"
                        route = "mac-local"
                        intent = try await MacIntentModel(model: self.conversation.preferences.macModel).classify(text)
                    } else {
                        self.status = "Using on-device intelligence"
                        route = "on-device"
                        intent = try await self.appleModel.classify(text)
                    }
                    try Task.checkCancellation()
                    if let intent, self.cacheGeneration == generation {
                        self.intentCache.insert(intent, text: text, model: source)
                    }
                }
                classified = true
                Signposts.signposter.endInterval("Assistant.Classify", classifying, "\(route, privacy: .public)")
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                await Signposts.measureAsync("Assistant.Card") { await self.handle(intent ?? .unsupported, input: text, app: app) }
            } catch is CancellationError { }
            catch {
                guard self.requestID == id else { return }
                self.append((error as? LocalizedError)?.errorDescription ?? "I couldn't understand that locally. Try a quick action below.")
            }
        }
    }
    func cancel() {
        Signposts.event("Assistant.Cancel")
        task?.cancel(); task = nil; requestID = nil; processing = false; status = ""
        append("Stopped. No proposed action was saved.")
    }
    func handle(_ intent: AssistantIntent, input: String, app: AppModel) async {
        let generation = cacheGeneration
        app.tick()
        switch intent {
        case .logCaffeine:
            expireDraft()
            pendingDraft = AssistantPlanner.caffeineDraft(input, doses: app.state.doses, now: app.now, clock: app.clock)
            pendingMessageID = appendCard(AssistantCards.make(.caffeineDraft, state: app.state, now: app.now, clock: app.clock, text: app.text), intent: intent)
            captureDraft(app: app)
        case .logSleep:
            expireDraft()
            pendingSleep = AssistantPlanner.usualNight(app.state.sleeps, now: app.now, clock: app.clock) ?? ManualSleep.newDraft(now: app.now)
            pendingMessageID = appendCard(AssistantCards.make(.sleepDraft, state: app.state, now: app.now, clock: app.clock, text: app.text), intent: intent)
            captureDraft(app: app)
        case .explainEnergy, .weeklyTrends, .reactionTest, .history, .exports, .reminders:
            let kind: AssistantCard.Kind = switch intent {
            case .weeklyTrends: .trends
            case .reactionTest: .reaction
            case .history: .history
            case .exports: .exports
            case .reminders: .reminders
            default: .energy
            }
            var card = AssistantCards.make(kind, state: app.state, now: app.now, clock: app.clock, text: app.text)
            if kind == .reminders { card.metrics = reminderMetrics(app: app) }
            appendCard(card, intent: intent)
        case .briefing:
            status = "Preparing your recorded day"
            var card = AssistantCards.make(.briefing, state: app.state, now: app.now, clock: app.clock, text: app.text)
            card.state = .loading
            let messageID = appendCard(card, intent: intent)
            await calendars.refreshCalendars(); await calendars.refresh()
            guard generation == cacheGeneration else { return }
            guard !Task.isCancelled else { updateCard(messageID) { $0.state = .failed; $0.summary = "Stopped. Refresh to review current commitments." }; return }
            updateCard(messageID) {
                $0.commitments = calendars.commitments.filter { app.clock.dayKey($0.start.timeIntervalSince1970 * 1000) == app.clock.dayKey(app.now) }
                $0.state = calendars.message == nil ? .ready : .failed
                if let error = calendars.message { $0.summary += "\n" + error }
            }
        case .calendar:
            status = "Reading selected commitments"
            var card = AssistantCards.make(.calendar, state: app.state, now: app.now, clock: app.clock, text: app.text)
            card.state = .loading
            let messageID = appendCard(card, intent: intent)
            await calendars.refreshCalendars(); await calendars.refresh()
            guard generation == cacheGeneration else { return }
            guard !Task.isCancelled else { updateCard(messageID) { $0.state = .failed; $0.summary = "Stopped. No calendar changes were made." }; return }
            updateCard(messageID) {
                $0.commitments = calendars.commitments
                $0.state = calendars.message == nil ? .ready : .failed
                $0.summary = calendars.message ?? "Nothing changes until you approve a preview."
            }
        case .energyProjection:
            appendCard(AssistantCards.make(.energyProjection, state: app.state, now: app.now, clock: app.clock, text: app.text), intent: intent)
        case .energyCheckIn:
            expireDraft()
            pendingCheckIn = .new(now: app.now, rating: AssistantPlanner.statedSelfRating(input))
            pendingMessageID = appendCard(AssistantCards.make(.energyCheckIn, state: app.state, now: app.now, clock: app.clock, text: app.text), intent: intent)
            captureDraft(app: app)
        case .cutoffScenario:
            openCutoff(app: app)
        case .settings: showAssistantSettings = true
        case .unsupported:
            appendCard(AssistantCards.make(.clarification, state: app.state, now: app.now, clock: app.clock, text: app.text), intent: intent)
        }
    }

    @discardableResult func appendCard(_ card: AssistantCard, intent: AssistantIntent? = nil) -> UUID {
        let message = ConversationMessage(text: card.title + (card.summary.isEmpty ? "" : ". " + card.summary), intent: intent, card: card)
        conversation.messages.append(message)
        activeCards.insert(message.id)
        save()
        return message.id
    }
    func updateCard(_ id: UUID?, change: (inout AssistantCard) -> Void) {
        guard let id, let index = conversation.messages.firstIndex(where: { $0.id == id }), var card = conversation.messages[index].card else { return }
        change(&card); conversation.messages[index].card = card; save()
    }
    func expireDraft() {
        updateCard(pendingMessageID) { $0.state = .expired }
        pendingDraft = nil; pendingSleep = nil; pendingCheckIn = nil; pendingMessageID = nil
        closeCutoff()
    }
    func captureDraft(app: AppModel) {
        if let draft = pendingDraft {
            updateCard(pendingMessageID) { $0.metrics = [
                .init(id: "amount", label: "Proposed amount", value: draft.mg.isEmpty ? "Not specified" : draft.mg + " mg", source: "User review required"),
                .init(id: "source", label: "Source", value: draft.source.isEmpty ? "Not specified" : draft.source, source: "Proposed entry"),
                .init(id: "time", label: "Time", value: app.text.fullDateTime(draft.timestamp), source: app.clock.timeZone.identifier)
            ] }
        } else if let draft = pendingSleep {
            updateCard(pendingMessageID) { $0.metrics = [
                .init(id: "start", label: "Start", value: app.text.fullDateTime(draft.start), source: "Manual · local time"),
                .init(id: "end", label: "End", value: app.text.fullDateTime(draft.end), source: "Manual · local time")
            ] }
        } else if let draft = pendingCheckIn {
            updateCard(pendingMessageID) { $0.metrics = [
                .init(id: "rating", label: "Your rating", value: draft.rating.map { EnergyCheckIn(id: draft.id, recordedAt: draft.recordedAt, rating: $0).ratingText } ?? "Not chosen", source: EnergyCheckIn.sourceLabel, missing: draft.rating == nil),
                .init(id: "time", label: "Time", value: app.text.fullDateTime(draft.recordedAt), source: app.clock.timeZone.identifier)
            ] }
        }
    }
    func discardDraft() {
        updateCard(pendingMessageID) { $0.state = .discarded }
        pendingDraft = nil; pendingSleep = nil; pendingCheckIn = nil; pendingMessageID = nil
        closeCutoff()
    }
    func refresh(_ card: AssistantCard, app: AppModel) {
        guard let intent = card.refreshIntent, !processing else { return }
        if card.kind == .cutoffScenario { refreshCutoff(card, app: app); return }
        let prompt: String = switch intent {
        case .logCaffeine: "Log caffeine"
        case .logSleep: "Log sleep"
        case .weeklyTrends: "Show this week"
        case .calendar: "Review calendar"
        case .reactionTest: "Reaction test"
        case .history: "History"
        case .exports: "Export records"
        case .briefing: "Morning briefing"
        case .reminders: "Reminders"
        case .energyProjection: "Show my energy curve"
        case .energyCheckIn: "Check in my energy"
        default: "How is my energy?"
        }
        send(prompt, app: app)
    }
    func reminderMetrics(app: AppModel) -> [AssistantCard.Metric] {
        let p = conversation.preferences
        return [
            .init(id: "cutoff", label: "Cutoff reminder", value: app.state.prefs.notifyCutoff ? app.text.clockHour(app.state.prefs.cutoffHour, clock: app.clock) : "Off", source: "Your selected time"),
            .init(id: "briefing", label: "Morning briefing", value: p.proactive && p.morningBriefing ? "\(p.briefingHour):00" : "Off", source: "Opt-in"),
            .init(id: "quiet", label: "Quiet hours", value: "\(p.quietStartHour):00–\(p.quietEndHour):00", source: "Up to two unsolicited suggestions daily")
        ]
    }
    func receipt(recordID: String, kind: String, app: AppModel, title: String) {
        var card = AssistantCard(kind: .receipt, capturedAt: app.now, title: title)
        card.state = .saved; card.recordID = recordID; card.recordKind = kind
        card.timeZone = app.clock.timeZone.identifier
        card.summary = title.contains("updated") ? "Correction recorded. Open history to review it." : "Entry recorded on this device."
        card.records = AssistantCards.make(.history, state: app.state, now: app.now, clock: app.clock, text: app.text).records.filter { $0.id == recordID && $0.kind == kind }
        if kind == "caffeine", let health = healthMetric(doseID: recordID, app: app) { card.metrics = [health] }
        let id = appendCard(card)
        if kind == "caffeine" { followHealth(doseID: recordID, messageID: id, app: app) }
    }

    /// The receipt's Apple Health row, apart from the local outcome in the
    /// title. Nil when Health has nothing to do with this entry.
    func healthMetric(doseID: String, app: AppModel) -> AssistantCard.Metric? {
        Self.healthMetric(app.healthStatus(forDoseID: doseID))
    }

    /// The same row for a given status; the Design Gallery shows each one.
    static func healthMetric(_ status: HealthExportStatus) -> AssistantCard.Metric? {
        guard let value = status.value else { return nil }
        return .init(id: "health", label: "Apple Health", value: value, source: "Aurora’s own entry", detail: status.detail, missing: status.needsAttention)
    }

    /// Waits for the entry's queued Health action, then updates the
    /// receipt's Apple Health row with what Health answered.
    func followHealth(doseID: String, messageID: UUID?, app: AppModel) {
        guard app.state.healthLedger.pendingAction(forDoseID: doseID) != nil else { return }
        Task {
            await app.healthSync.runPendingActions(for: [doseID])
            updateCard(messageID) { card in
                card.metrics.removeAll { $0.id == "health" }
                if let health = healthMetric(doseID: doseID, app: app) { card.metrics.append(health) }
            }
        }
    }

    /// A plain message for a removal outside a receipt, with Health's
    /// part reported on its own line.
    func appendRemoval(_ text: String, doseID: String, app: AppModel) {
        func line() -> String { healthMetric(doseID: doseID, app: app).map { "Apple Health: \($0.value). \($0.detail)" } ?? "" }
        let before = line()
        append(before.isEmpty ? text : text + "\n" + before)
        guard app.state.healthLedger.pendingAction(forDoseID: doseID) != nil else { return }
        Task {
            await app.healthSync.runPendingActions(for: [doseID])
            let after = line()
            if !after.isEmpty && after != before { append(after) }
        }
    }
    func saveSleep(app: AppModel) {
        guard let draft = pendingSleep else { return }
        app.tick()
        if let error = ManualSleep.validate(start: draft.start, end: draft.end, now: app.now).message { failure = error; return }
        let previous = Set(app.state.sleeps.map(\.id))
        app.addManualSleep(draft)
        guard app.mutationFailure == nil, let added = app.state.sleeps.first(where: { !previous.contains($0.id) }) else { failure = app.mutationFailure ?? "The sleep entry wasn't saved."; return }
        updateCard(pendingMessageID) { $0.state = .saved }
        pendingSleep = nil; pendingMessageID = nil
        receipt(recordID: added.id, kind: "sleep", app: app, title: "Sleep saved")
    }
    func undoReceipt(_ message: ConversationMessage, app: AppModel) {
        guard let card = conversation.messages.first(where: { $0.id == message.id })?.card, card.state == .saved, let id = card.recordID, let kind = card.recordKind else { return }
        app.tick()
        let current = AssistantCards.make(.history, state: app.state, now: app.now, clock: app.clock, text: app.text).records.first { $0.id == id && $0.kind == kind }
        guard let current, current.editable, card.records.first == current else { failure = "This record changed or is no longer available. Open history to review it."; return }
        if card.title.lowercased().contains("updated") { failure = "Open history to review a correction."; return }
        if kind == "caffeine", let dose = app.state.doses.first(where: { $0.id == id }) { app.undo(dose) }
        else if kind == "sleep" { app.deleteManualSleep(id: id) }
        else { return }
        guard app.mutationFailure == nil else { failure = app.mutationFailure; return }
        updateCard(message.id) {
            $0.state = .undone; $0.title = "Entry removed"; $0.summary = "Removed that \(kind) entry on this device. Other records are unchanged."
            $0.metrics.removeAll { $0.id == "health" }
            if kind == "caffeine", let health = healthMetric(doseID: id, app: app) { $0.metrics.append(health) }
        }
        if kind == "caffeine" { followHealth(doseID: id, messageID: message.id, app: app) }
        savedDose = nil
    }
    // MARK: Energy check-ins

    /// Saves the open check-in. A repeated tap finds no open review, and the
    /// review's fixed id means the record can't be added twice. A failed
    /// write keeps the review open with the same id, so Save can be retried.
    func saveCheckIn(app: AppModel) {
        guard let draft = pendingCheckIn else { return }
        app.tick()
        if let message = draft.validate(now: app.now).message { failure = message; return }
        guard let checkIn = draft.checkIn else { return }
        let saved = draft.original.map { app.replaceEnergyCheckIn(checkIn, expecting: $0) } ?? app.addEnergyCheckIn(checkIn)
        guard saved, app.mutationFailure == nil else { failure = app.mutationFailure ?? "The check-in wasn't saved."; return }
        failure = nil
        updateCard(pendingMessageID) { $0.state = .saved }
        pendingCheckIn = nil; pendingMessageID = nil
        var card = AssistantCard(kind: .receipt, capturedAt: app.now, title: draft.original == nil ? "Check-in saved" : "Check-in updated")
        card.state = .saved; card.recordID = checkIn.id; card.recordKind = "checkin"
        card.timeZone = app.clock.timeZone.identifier
        card.summary = "Your rating, saved on this device. It is not part of the model."
        card.checkIn = .init(saved: checkIn, previous: draft.original)
        appendCard(card)
    }

    /// Undo removes a new check-in, or restores the rating a correction
    /// replaced, only while the saved record is unchanged.
    func undoCheckIn(_ message: ConversationMessage, app: AppModel) {
        guard let card = conversation.messages.first(where: { $0.id == message.id })?.card, card.state == .saved,
              let saved = card.checkIn?.saved else { return }
        let previous = card.checkIn?.previous
        let done = previous.map { app.replaceEnergyCheckIn($0, expecting: saved) } ?? app.removeEnergyCheckIn(saved)
        guard done, app.mutationFailure == nil else {
            failure = "This check-in changed or was removed. Nothing else was changed."
            return
        }
        failure = nil
        updateCard(message.id) {
            $0.state = .undone
            $0.title = previous == nil ? "Check-in removed" : "Correction undone"
            $0.summary = previous == nil ? "Removed that check-in on this device. Other records are unchanged." : "Restored the earlier rating. Other records are unchanged."
        }
    }

    /// Opens a correction review for the receipt's check-in, if unchanged.
    func editCheckIn(_ message: ConversationMessage, app: AppModel) {
        guard let saved = message.card?.checkIn?.saved, app.state.energyCheckIns.contains(saved) else {
            failure = "This check-in changed or was removed. Nothing else was changed."
            return
        }
        app.tick()
        expireDraft()
        pendingCheckIn = .editing(saved)
        var card = AssistantCards.make(.energyCheckIn, state: app.state, now: app.now, clock: app.clock, text: app.text)
        card.title = "Edit check-in"
        pendingMessageID = appendCard(card, intent: .energyCheckIn)
        captureDraft(app: app)
    }

    func reactionCompleted(app: AppModel) {
        guard started, !app.state.vigilanceSessions.isEmpty else { return }
        var card = AssistantCards.make(.reaction, state: app.state, now: app.now, clock: app.clock, text: app.text)
        card.title = "Reaction Test recorded"; card.state = .saved
        appendCard(card, intent: .reactionTest)
    }

    func saveDose(app: AppModel) {
        guard let draft = pendingDraft else { return }
        app.tick()
        if let message = CaffeineLog.validate(draft, now: app.now).message { failure = message; return }
        let dose = app.addCustomDose(draft)
        guard app.mutationFailure == nil else { failure = app.mutationFailure; return }
        updateCard(pendingMessageID) { $0.state = .saved }
        savedDose = dose; pendingDraft = nil; pendingMessageID = nil
        receipt(recordID: dose.id, kind: "caffeine", app: app, title: "Caffeine saved")
        Haptics.success()
    }
    func undoDose(app: AppModel) {
        guard let dose = savedDose, app.state.doses.contains(dose) else { savedDose = nil; return }
        app.undo(dose)
        guard app.mutationFailure == nil else { failure = app.mutationFailure; return }
        savedDose = nil; appendRemoval("Removed that caffeine entry on this device. Other records are unchanged.", doseID: dose.id, app: app)
    }
    func dismissSuggestion(_ message: ConversationMessage) {
        if let key = message.suggestionKey { conversation.dismissedSuggestions.insert(key) }
        conversation.messages.removeAll { $0.id == message.id }
        save()
    }
    /// Refreshes calendars and offers suggestions, as the shared refresh
    /// decides. Suggestions keep their opt-in, quiet hours, daily limits and
    /// dismissals.
    func foreground(app: AppModel, steps: Set<RefreshPolicy.Step> = [.calendars, .suggestions]) async {
        guard started, conversation.preferences.proactive else { return }
        let generation = cacheGeneration
        if steps.contains(.calendars) { await calendars.refresh() }
        guard steps.contains(.suggestions) else { return }
        guard generation == cacheGeneration, app.phase == .ready, conversation.preferences.proactive else { return }
        guard !Task.isCancelled else { return }
        app.tick()
        let day = app.clock.dayKey(app.now)
        var suggestions: [(String, String)] = []
        if conversation.preferences.morningBriefing && app.clock.hour(app.now) >= conversation.preferences.briefingHour {
            suggestions.append(("brief:\(day)", "Your daily briefing\n\n" + AssistantPlanner.energyExplanation(state: app.state, now: app.now, clock: app.clock)))
        }
        if let sleep = SleepChangeSuggestion.latest(app.state.sleeps, now: app.now) {
            suggestions.append(sleep)
        }
        if let upcoming = calendars.commitments.first(where: { $0.start > .now && $0.start.timeIntervalSinceNow < 3600 }) {
            suggestions.append(("calendar:\(upcoming.identity):\(upcoming.revision)", "You have a commitment coming up: \(upcoming.title). Ask me to review your afternoon if your plans have changed."))
        }
        for (key, text) in suggestions where ProactivePolicy.canDeliver(key: key, state: conversation, now: app.now, clock: app.clock) {
            deliverSuggestion(key: key, text: text, app: app)
        }
        save()
    }

    /// After recorded sleep changed (a Health import or a manual entry):
    /// offers only the sleep suggestion, only if the relevant sleep actually
    /// changed, under the same opt-in policy. No model is involved.
    func sleepChanged(app: AppModel, before: [SleepSession]) {
        guard started, app.phase == .ready else { return }
        app.tick()
        guard let (key, text) = SleepChangeSuggestion.afterChange(
            before: before, after: app.state.sleeps, conversation: conversation, now: app.now, clock: app.clock
        ) else { return }
        deliverSuggestion(key: key, text: text, app: app)
        save()
    }

    private func deliverSuggestion(key: String, text: String, app: AppModel) {
        conversation.deliveredSuggestions[key] = app.now
        var card = AssistantCards.make(.briefing, state: app.state, now: app.now, clock: app.clock, text: app.text)
        card.commitments = calendars.commitments.filter { app.clock.dayKey($0.start.timeIntervalSince1970 * 1000) == app.clock.dayKey(app.now) }
        card.summary = key.hasPrefix("brief:") ? card.summary : text
        conversation.messages.append(.init(text: text, intent: .briefing, suggestionKey: key, card: card))
    }

    func syncBriefingNotification(prompt: Bool) async {
        let generation = cacheGeneration
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["aurora.assistant.briefing"])
        guard conversation.preferences.proactive, conversation.preferences.morningBriefing else { return }
        if prompt { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
        let settings = await center.notificationSettings()
        guard generation == cacheGeneration else { return }
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { failure = "Notifications are off. Your briefing will appear when you open Aurora."; return }
        let p = conversation.preferences
        let hour = p.briefingHour
        let quiet = p.quietStartHour == p.quietEndHour || (p.quietStartHour > p.quietEndHour ? hour >= p.quietStartHour || hour < p.quietEndHour : hour >= p.quietStartHour && hour < p.quietEndHour)
        guard !quiet else { failure = "Choose a briefing time outside quiet hours."; return }
        let content = UNMutableNotificationContent(); content.title = "Your Aurora briefing"; content.body = "Open Aurora to review today’s recorded energy and commitments."
        var date = DateComponents(); date.hour = hour; date.minute = 0
        do {
            try await center.add(.init(identifier: "aurora.assistant.briefing", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)))
            if generation != cacheGeneration { center.removePendingNotificationRequests(withIdentifiers: ["aurora.assistant.briefing"]) }
        }
        catch { failure = "Couldn't schedule the briefing notification." }
    }
}
