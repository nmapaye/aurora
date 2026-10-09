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
    var activeCards: Set<UUID> = []
    var savedDose: Dose?
    var showSleepEntry = false
    var showCalendarSettings = false
    var showAssistantSettings = false
    var historySheet: AssistantIntent?
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
        self.calendars = calendars ?? CalendarService(); self.makeConversationStore = makeStore
    }

    var intelligenceName: String {
        if conversation.preferences.useMacModel { return "Mac local · \(conversation.preferences.macModel)" }
        return AppleIntentModel.available ? "On-device intelligence" : "Local quick actions · AI unavailable"
    }

    func start(app: AppModel) async {
        guard !started else { return }
        started = true
        do {
            let store = try makeConversationStore()
            self.store = store
            conversation = ProcessInfo.processInfo.arguments.contains("-AuroraUITestReset") ? ConversationState() : try store.load()
            storageReady = true
            for index in conversation.messages.indices {
                if let card = conversation.messages[index].card {
                    if card.state == .loading {
                        conversation.messages[index].card?.state = .failed
                        conversation.messages[index].card?.summary = "This request didn't finish. Refresh for a current result."
                    } else if [.caffeineDraft, .sleepDraft, .calendar].contains(card.kind), card.state == .ready {
                        conversation.messages[index].card?.state = .expired
                    }
                }
            }
            if conversation.messages.isEmpty {
                appendCard(AssistantCards.make(.clarification, state: app.state, now: app.now, clock: app.clock, text: app.text))
            }
            if app.state.isWalkthroughPending { app.completeWalkthrough() }
            await calendars.refreshCalendars()
            await foreground(app: app)
        } catch {
            failure = "Your conversation couldn't be opened. It has been preserved. Records and native tools remain available."
        }
    }

    func prepareForInput() {
        guard !processing, !conversation.preferences.useMacModel else { return }
        appleModel.prewarm()
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
        conversation = cleared; pendingDraft = nil; pendingSleep = nil
        pendingMessageID = nil; activeCards = []; savedDose = nil
        releaseWarmResources()
        do { try store?.removeMigrationSource() }
        catch { failure = "The conversation was cleared, but its migration source couldn't be removed. Please retry." }
    }

    func resetAfterErase() {
        task?.cancel(); task = nil; requestID = nil; processing = false; status = ""
        conversation = ConversationState(); pendingDraft = nil; pendingSleep = nil
        pendingMessageID = nil; activeCards = []; savedDose = nil; historySheet = nil
        showSleepEntry = false; showCalendarSettings = false; showAssistantSettings = false
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
        processing = true; status = "Understanding your request"; failure = nil
        let id = UUID(); requestID = id
        let generation = cacheGeneration
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.requestID == id { self.processing = false; self.status = ""; self.task = nil }
            }
            do {
                var intent = AssistantPlanner.explicitIntent(text)
                if intent == nil {
                    let source = self.conversation.preferences.useMacModel
                        ? "mac:\(self.conversation.preferences.macModel)" : "apple"
                    if let cached = self.intentCache.lookup(text, model: source) {
                        self.status = "Checking your request"
                        intent = cached
                    } else if self.conversation.preferences.useMacModel {
                        self.status = "Asking your Mac’s local model"
                        intent = try await MacIntentModel(model: self.conversation.preferences.macModel).classify(text)
                    } else {
                        self.status = "Using on-device intelligence"
                        intent = try await self.appleModel.classify(text)
                    }
                    try Task.checkCancellation()
                    if let intent, self.cacheGeneration == generation {
                        self.intentCache.insert(intent, text: text, model: source)
                    }
                }
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                await self.handle(intent ?? .unsupported, input: text, app: app)
            } catch is CancellationError { }
            catch {
                guard self.requestID == id else { return }
                self.append((error as? LocalizedError)?.errorDescription ?? "I couldn't understand that locally. Try a quick action below.")
            }
        }
    }
    func cancel() {
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
        pendingDraft = nil; pendingSleep = nil; pendingMessageID = nil
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
        }
    }
    func discardDraft() {
        updateCard(pendingMessageID) { $0.state = .discarded }
        pendingDraft = nil; pendingSleep = nil; pendingMessageID = nil
    }
    func refresh(_ card: AssistantCard, app: AppModel) {
        guard let intent = card.refreshIntent, !processing else { return }
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
        appendCard(card)
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
        updateCard(message.id) { $0.state = .undone; $0.title = "Entry removed"; $0.summary = "Removed that \(kind) entry. Other records are unchanged." }
        savedDose = nil
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
        savedDose = nil; append("Removed that caffeine entry. Other records are unchanged.")
    }
    func dismissSuggestion(_ message: ConversationMessage) {
        if let key = message.suggestionKey { conversation.dismissedSuggestions.insert(key) }
        conversation.messages.removeAll { $0.id == message.id }
        save()
    }
    func foreground(app: AppModel) async {
        guard started, conversation.preferences.proactive else { return }
        let generation = cacheGeneration
        await calendars.refresh()
        guard generation == cacheGeneration, app.phase == .ready, conversation.preferences.proactive else { return }
        guard !Task.isCancelled else { return }
        app.tick()
        let day = app.clock.dayKey(app.now)
        var suggestions: [(String, String)] = []
        if conversation.preferences.morningBriefing && app.clock.hour(app.now) >= conversation.preferences.briefingHour {
            suggestions.append(("brief:\(day)", "Your daily briefing\n\n" + AssistantPlanner.energyExplanation(state: app.state, now: app.now, clock: app.clock)))
        }
        if let sleep = app.state.sleeps.filter({ !RecordID.isSample($0.id) && $0.end <= app.now && $0.end > app.now - dayMs }).max(by: { $0.end < $1.end }) {
            suggestions.append(("sleep:\(sleep.id):\(sleep.end)", "Your recorded sleep has updated. You can ask ‘How is my energy?’ to review the current estimate."))
        }
        if let upcoming = calendars.commitments.first(where: { $0.start > .now && $0.start.timeIntervalSinceNow < 3600 }) {
            suggestions.append(("calendar:\(upcoming.identity):\(upcoming.revision)", "You have a commitment coming up: \(upcoming.title). Ask me to review your afternoon if your plans have changed."))
        }
        for (key, text) in suggestions where ProactivePolicy.canDeliver(key: key, state: conversation, now: app.now, clock: app.clock) {
            conversation.deliveredSuggestions[key] = app.now
            var card = AssistantCards.make(.briefing, state: app.state, now: app.now, clock: app.clock, text: app.text)
            card.commitments = calendars.commitments.filter { app.clock.dayKey($0.start.timeIntervalSince1970 * 1000) == app.clock.dayKey(app.now) }
            card.summary = key.hasPrefix("brief:") ? card.summary : text
            conversation.messages.append(.init(text: text, intent: .briefing, suggestionKey: key, card: card))
        }
        save()
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
