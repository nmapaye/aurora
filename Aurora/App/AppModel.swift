import AuroraCore
import Foundation
import Observation
import SwiftUI

/// Owns Aurora's state. Every change goes through an `AppState` action and is
/// saved right away, so a just-saved record shows everywhere at once and
/// survives a relaunch.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loading
        /// Backup exclusion couldn't be confirmed, so no records are read.
        case storageUnavailable
        case ready
    }

    private(set) var phase: Phase = .loading
    private(set) var state = AppState()
    /// Moves every minute and on foreground, so "today" rolls over at midnight.
    private(set) var now: Millis = AppModel.currentMillis()
    /// Shown once when the old app's file couldn't be read.
    var legacyImportFailed = false
    private(set) var mutationFailure: String?
    private(set) var reminderStatus: ReminderService.Status = .off
    var pendingLink: DeepLink?

    let clock: LocalClock
    let text: DateText
    let health: any HealthDataProvider
    let reminders: ReminderService
    private let makeStore: () throws -> StateStore
    private let legacy: () -> LegacyImport?
    private let makeDeletion: (StateStore, LegacyImport?) -> LocalDataDeletion
    private var store: StateStore?
    private var lastQuickAddAt: Millis?
    private var dataGeneration = 0
    /// Caffeine reads, observers and the outbox of Aurora's own Health writes.
    @ObservationIgnored private(set) var healthSync: HealthSyncEngine!
    /// The one refresh path for foreground, background and Health changes.
    @ObservationIgnored private(set) var refresher: RefreshScheduler!
    @ObservationIgnored private var lastRefresh: [RefreshPolicy.Step: Millis] = [:]
    @ObservationIgnored private var healthExportDispatch: Task<Void, Never>?
    /// Calendars and suggestions, run by the assistant inside a refresh.
    @ObservationIgnored var assistantRefresh: (@MainActor (Set<RefreshPolicy.Step>) async -> Void)?
    /// Recorded sleep changed during a refresh; receives the sleep before.
    @ObservationIgnored var sleepChanged: (@MainActor ([SleepSession]) -> Void)?
    private var nextActionID: () -> String = { UUID().uuidString.lowercased() }

    init(
        clock: LocalClock = .current,
        text: DateText = .current,
        health: any HealthDataProvider = HealthKitService(),
        reminders: ReminderService? = nil,
        makeStore: @escaping () throws -> StateStore = StateStore.live,
        legacy: @escaping () -> LegacyImport? = LegacyImport.live,
        makeDeletion: ((StateStore, LegacyImport?) -> LocalDataDeletion)? = nil
    ) {
        self.clock = clock
        self.text = text
        self.health = health
        self.reminders = reminders ?? ReminderService()
        self.makeStore = makeStore
        self.legacy = legacy
        self.makeDeletion = makeDeletion ?? { LocalDataDeletion(store: $0, legacy: $1) }
        healthSync = HealthSyncEngine(provider: health, host: HealthSyncEngine.Host(
            state: { [unowned self] in self.state },
            commit: { [unowned self] change in self.update(change) },
            now: { [unowned self] in self.tick(); return self.now }
        ))
        refresher = RefreshScheduler { [weak self] triggers, isCurrent in
            await self?.performRefresh(triggers, isCurrent: isCurrent)
        }
        healthSync.onChange = { [weak self] kind in
            await self?.refresher.request(.healthChange(kind))
        }
    }

    static func currentMillis() -> Millis {
        (Date.now.timeIntervalSince1970 * 1000).rounded()
    }

    func tick() {
        now = Self.currentMillis()
    }

    // MARK: Loading and saving

    func load() {
        guard phase != .ready else { return }
        do {
            let store = try makeStore()
            try store.prepare()
            self.store = store
            let deletion = makeDeletion(store, legacy())
            if deletion.pending {
                do { try deletion.finish(); mutationFailure = nil }
                catch {
                    mutationFailure = "Local data erase is incomplete. Retry to finish erasing; records will not be restored. " + error.localizedDescription
                    throw error
                }
            }
            tick()
            if let saved = try store.load() {
                state = saved
            } else if let legacy = legacy() {
                switch legacy.read(now: now) {
                case .imported(let imported):
                    state = imported
                    try store.save(state)
                    guard try store.load() == state else { throw StateStore.Failure.verificationFailed }
                    // Keep the MMKV source for rollback and later migration inspection.
                case .unreadable:
                    legacyImportFailed = true
                case .none:
                    break
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-AuroraUITestReset") {
                state = AppState()
            }
            phase = .ready
        } catch {
            phase = .storageUnavailable
        }
    }

    func retryStorage() {
        phase = .loading
        load()
    }

    /// Applies and saves a change; on failure the previous state stays.
    @discardableResult
    private func update(_ change: (inout AppState) -> Void) -> Bool {
        guard phase == .ready else { return false }
        let previous = state
        mutationFailure = nil
        change(&state)
        do {
            guard let store else { throw StateStore.Failure.verificationFailed }
            try store.save(state)
            return true
        } catch {
            state = previous
            mutationFailure = "Couldn't save this change. Your previous records are preserved."
            return false
        }
    }

    // MARK: Caffeine

    /// Quick Add. A second tap within a second is ignored as a double tap.
    func quickAdd(_ preset: CaffeinePreset) -> Dose? {
        tick()
        guard CaffeineLog.acceptsQuickAdd(lastAcceptedAt: lastQuickAddAt, at: now) else { return nil }
        lastQuickAddAt = now
        let dose = CaffeineLog.quickAddDose(preset, now: now, id: RecordID.newDoseID(now: now))
        let action = nextActionID()
        if update({ $0.addDose(dose); $0.queueHealthSave(doseID: dose.id, now: now, id: action) }) { exportToHealth(dose.id) }
        return dose
    }

    func addCustomDose(_ draft: CustomDoseDraft) -> Dose {
        tick()
        let dose = CaffeineLog.customDose(draft, id: RecordID.newDoseID(now: now))
        if let failure = CaffeineLog.validate(draft, now: now).message {
            mutationFailure = failure
            return dose
        }
        let action = nextActionID()
        if update({ $0.addDose(dose); $0.queueHealthSave(doseID: dose.id, now: now, id: action) }) { exportToHealth(dose.id) }
        return dose
    }

    func correctDose(id: String, with draft: CustomDoseDraft) {
        guard let dose = state.doses.first(where: { $0.id == id }), CaffeineLog.isEditable(dose) else { return }
        tick()
        let action = nextActionID()
        if update({ $0.updateDose(id: id, with: CaffeineLog.patch(from: draft)); $0.queueHealthCorrection(doseID: id, now: now, id: action) }) {
            exportToHealth(id)
        }
    }

    func deleteDose(id: String) {
        guard let dose = state.doses.first(where: { $0.id == id }), CaffeineLog.isEditable(dose) else { return }
        removeDose(id)
    }

    /// Undo for the dose Quick Add just logged. `AppState` refuses to remove
    /// Health caffeine, so a stale receipt can't delete it.
    func undo(_ dose: Dose) {
        guard state.doses.contains(where: { $0.id == dose.id }), CaffeineLog.isEditable(dose) else { return }
        removeDose(dose.id)
    }

    /// Removes the dose here first; only Aurora's own copy in Health is then
    /// queued for removal.
    private func removeDose(_ id: String) {
        tick()
        let action = nextActionID()
        if update({ $0.removeDose(id: id); $0.queueHealthRemoval(doseID: id, now: now, id: action) }) { exportToHealth(id) }
    }

    /// Runs the dose's queued Health action, if any, after the local change
    /// is stored. Receipts read `healthStatus(forDoseID:)`, which updates
    /// when Health answers.
    private func exportToHealth(_ doseID: String) {
        guard state.healthLedger.pendingAction(forDoseID: doseID) != nil else { return }
        let previous = healthExportDispatch
        let generation = dataGeneration
        healthExportDispatch = Task {
            await previous?.value
            guard !Task.isCancelled, generation == dataGeneration else { return }
            await healthSync.runPendingActions(for: [doseID])
        }
    }

    /// Await automatic dispatches already queued by local record changes.
    /// This does not retry failed exports or wait for future record changes.
    func waitForHealthExports() async {
        await healthExportDispatch?.value
    }

    func healthStatus(forDoseID id: String) -> HealthExportStatus {
        HealthExportStatus.of(doseID: id, state: state)
    }

    /// Explicit Retry: runs every queued Health action, checking for an
    /// interrupted write before writing again.
    func retryHealthExports() async {
        await healthSync.runPendingActions()
    }

    // MARK: Sleep

    func addManualSleep(_ draft: ManualSleep.Draft) {
        tick()
        if let failure = ManualSleep.validate(start: draft.start, end: draft.end, now: now).message {
            mutationFailure = failure
            return
        }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = SleepSession(
            id: RecordID.newManualSleepID(now: now), start: draft.start, end: draft.end, type: .sleep,
            note: note.isEmpty ? nil : note
        )
        update { $0.addSleep(session) }
    }

    func correctManualSleep(id: String, with draft: ManualSleep.Draft) {
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        update { $0.updateManualSleep(id: id, start: draft.start, end: draft.end, note: .some(note.isEmpty ? nil : note)) }
    }

    func deleteManualSleep(id: String) {
        update { $0.removeManualSleep(id: id) }
    }

    // MARK: Health

    var healthAvailable: Bool { health.isAvailable }

    /// Asks for read access, then imports. Used by onboarding and Sleep.
    func connectHealth(importDays: Double = HealthImport.refreshDays, failurePrefix: String = "Health refresh failed.") async {
        let generation = dataGeneration
        tick()
        guard health.isAvailable else {
            update {
                $0.onboarding.source = .manual
                $0.onboarding.permissionStatus = .unsupported
                $0.healthSync = HealthSync(lastSyncedAt: now, lastMessage: SleepDataStatus.unavailableMessage, importedCount: 0, importStatus: .idle)
            }
            return
        }
        do {
            try await health.requestAuthorization(read: [.sleepAnalysis], write: [])
        } catch {
            guard generation == dataGeneration else { return }
            tick()
            update {
                $0.onboarding.source = .manual
                $0.onboarding.permissionStatus = .denied
                $0.healthSync = HealthSync(lastSyncedAt: now, lastMessage: SleepDataStatus.notSetUpMessage, importedCount: 0, importStatus: .idle)
            }
            return
        }
        guard generation == dataGeneration else { return }
        update {
            $0.onboarding.source = .healthkit
            $0.onboarding.permissionStatus = .granted
            $0.healthChoices.readSleep = true
        }
        await importHealth(days: importDays, failurePrefix: failurePrefix)
        await healthSync.startObservers()
        await healthSync.reconcileBackgroundDelivery()
    }

    /// Reads Health sleep. A provider with sample identity uses the anchored
    /// read (UUIDs, sources, deletions); otherwise the window import, which
    /// identifies sleep by interval.
    func importHealth(days: Double = HealthImport.refreshDays, failurePrefix: String = "Health refresh failed.") async {
        let generation = dataGeneration
        let sleepGeneration = healthSync.readGeneration(.sleepAnalysis)
        var current: Bool { generation == dataGeneration && sleepGeneration == healthSync.readGeneration(.sleepAnalysis) }
        let anchored = health.capabilities.contains(.readSleepChanges)
        if anchored && (!state.healthChoices.readSleep || state.demoMode) { return }
        tick()
        let end = now
        update {
            $0.healthSync.importStatus = .importing
            $0.healthSync.lastMessage = HealthImport.importingMessage
        }
        // A stale import must not leave "importing" behind, which would
        // block later refreshes.
        func settleIfStale() {
            if state.healthSync.importStatus == .importing { update { $0.healthSync.importStatus = .idle } }
        }
        if anchored {
            switch await healthSync.readSleepChanges() {
            case .failed(let message):
                guard current else { return settleIfStale() }
                tick()
                update { HealthImport.recordFailure(message, prefix: failurePrefix, now: self.now, to: &$0) }
            case .appliedSleep, .applied:
                break
            case .skipped, .discarded, .notSaved:
                settleIfStale()
            }
            return
        }
        do {
            let samples = try await health.sleepSamples(from: end - days * dayMs, to: end)
            guard current else { return settleIfStale() }
            tick()
            update { _ = HealthImport.apply(samples, days: days, now: end, to: &$0) }
        } catch {
            guard current else { return settleIfStale() }
            tick()
            let message = (error as? LocalizedError)?.errorDescription ?? "Unable to read sleep data."
            update { HealthImport.recordFailure(message, prefix: failurePrefix, now: self.now, to: &$0) }
        }
    }

    /// Runs whenever Aurora becomes active: keeps the reminder current, then
    /// refreshes through the shared scheduler. Never prompts.
    func foregroundSync() async {
        tick()
        guard phase == .ready, state.onboarding.completed else { return }
        reminderStatus = await reminders.sync(enabled: state.prefs.notifyCutoff, cutoffHour: state.prefs.cutoffHour, prompt: false)
        await healthSync.startObservers()
        await refresher.request(.foreground)
    }

    /// For a granted background opportunity or an explicit Refresh.
    func refresh(_ trigger: RefreshTrigger) async {
        tick()
        guard phase == .ready, state.onboarding.completed else { return }
        await healthSync.startObservers()
        await refresher.request(trigger)
    }

    /// One coalesced refresh: Health sleep and caffeine when chosen and due,
    /// then calendars and suggestions through the assistant. Every step stops
    /// once an erase or disconnect has made the run stale.
    private func performRefresh(_ triggers: Set<RefreshTrigger>, isCurrent: @escaping @MainActor () -> Bool) async {
        tick()
        guard phase == .ready, state.onboarding.completed else { return }
        let steps = RefreshPolicy.steps(for: triggers, lastRun: lastRefresh, now: now)
        let started = now
        let forced = triggers.contains(.explicit) || triggers.contains(.healthChange(.sleepAnalysis))
        let sleepsBefore = state.sleeps
        if steps.contains(.healthSleep), state.healthChoices.readSleep, !state.demoMode,
           state.healthSync.importStatus != .importing, forced || HealthImport.shouldRefresh(state: state, now: now) {
            await importHealth()
            // A partial read stays due, so the next opportunity continues it.
            if state.healthSync.importStatus != .partial { lastRefresh[.healthSleep] = started }
        }
        guard isCurrent() else { return }
        // Health-change runs don't evaluate suggestions in general; a real
        // change to relevant sleep still gets its one policy-checked offer.
        if !steps.contains(.suggestions), state.sleeps != sleepsBefore { sleepChanged?(sleepsBefore) }
        if steps.contains(.healthCaffeine) {
            let read = await healthSync.readCaffeineChanges()
            if case .applied(let result) = read, result.hasMore { } else { lastRefresh[.healthCaffeine] = started }
        }
        guard isCurrent() else { return }
        let assistantSteps = Set(steps).intersection([.calendars, .suggestions])
        if !assistantSteps.isEmpty, let assistantRefresh {
            await assistantRefresh(assistantSteps)
            if assistantSteps.contains(.calendars) { lastRefresh[.calendars] = started }
        }
    }

    /// After a read failed because its stored position couldn't be decoded.
    func restartHealthReading(_ kind: HealthDataKind) async {
        guard healthSync.restartReading(kind) else { return }
        await refresher.request(.explicit)
    }

    /// Turns one Health permission on or off. Turning on shows Health's
    /// sheet for that permission alone; reads then refresh right away.
    @discardableResult
    func setHealthChoice(_ choice: HealthChoice, enabled: Bool) async -> HealthSyncEngine.ChoiceResult {
        if choice == .readSleep && enabled {
            await connectHealth()
            return state.healthChoices.readSleep ? .requested : .failed(state.healthSync.lastMessage ?? "Health access wasn’t set up.")
        }
        let result = await healthSync.setChoice(choice, enabled: enabled)
        if result == .requested, choice == .readCaffeine { await refresher.request(.explicit) }
        return result
    }

    /// Stops Health work for Delete All Records or full erase. Copies Aurora
    /// already added to Health stay there.
    private func cancelHealthWork() {
        dataGeneration += 1
        healthExportDispatch?.cancel()
        healthSync.invalidateAll()
        refresher.invalidate()
        lastRefresh = [:]
    }

    // MARK: Settings

    func setPrefs(_ change: (inout Prefs) -> Void) {
        update { change(&$0.prefs) }
    }

    func setAppearance(_ mode: AppearanceMode) {
        update { $0.appearanceMode = mode }
    }

    func setReminder(enabled: Bool) async {
        update { $0.prefs.notifyCutoff = enabled }
        reminderStatus = await reminders.sync(enabled: enabled, cutoffHour: state.prefs.cutoffHour, prompt: enabled)
    }

    func resyncReminder() async {
        reminderStatus = await reminders.sync(enabled: state.prefs.notifyCutoff, cutoffHour: state.prefs.cutoffHour, prompt: false)
    }

    // MARK: Sample Data and deletion

    func loadSampleData() {
        tick()
        update {
            $0.loadSampleData(now: now, clock: clock)
            $0.doses.removeAll { RecordID.isSample($0.id) && $0.timestamp > now }
            $0.sleeps.removeAll { RecordID.isSample($0.id) && $0.end > now }
            $0.vigilanceSessions.removeAll { RecordID.isSample($0.id) && $0.completedAt > now }
        }
    }

    func clearSampleData() {
        update { $0.clearSampleData() }
    }

    /// Health choices stay, so observers restart and the next read imports
    /// Health records again, Aurora's earlier copies as read-only entries.
    func deleteAllData() {
        cancelHealthWork()
        update { $0.deleteAllData() }
        Task { await healthSync.startObservers() }
    }

    /// Explicitly confirmed full erase, separate from record-only deletion.
    func eraseAllLocalData(assistant: AssistantModel) -> Bool {
        guard let store else { return false }
        let deletion = makeDeletion(store, legacy())
        do { try deletion.begin() }
        catch { mutationFailure = "Couldn't start deletion. Your local data is preserved."; return false }
        cancelHealthWork()
        reminders.cancelForErase()
        phase = .loading
        assistant.resetAfterErase()
        state = AppState(); lastQuickAddAt = nil; pendingLink = nil
        reminderStatus = .off; legacyImportFailed = false
        do {
            try deletion.finish()
            mutationFailure = nil; phase = .ready
            return true
        } catch {
            mutationFailure = "Deletion is incomplete. Retry before reopening data. " + error.localizedDescription
            phase = .storageUnavailable
            return false
        }
    }

    // MARK: Reaction Test

    func saveReactionTest(_ session: VigilanceSession, hasTimedResponse: Bool? = nil) {
        guard hasTimedResponse ?? (session.validReactionCount > 0) else { return }
        update { $0.addVigilanceSession(session) }
    }

    // MARK: Onboarding and walkthrough

    func setSleepTarget(_ hours: Double) {
        update { $0.prefs.targetSleep = hours }
    }

    func chooseSleepSource(_ source: OnboardingSource) {
        update {
            $0.onboarding.source = source
            $0.onboarding.permissionStatus = source == .manual ? .unsupported : .idle
            if source == .manual { $0.healthChoices.readSleep = false }
        }
    }

    /// First-run Health request: read access, then a 14-day import. The
    /// chosen source stays as picked whatever the outcome.
    func requestHealthForOnboarding() async {
        guard health.isAvailable else {
            update { $0.onboarding.permissionStatus = .unsupported }
            return
        }
        do {
            try await health.requestAuthorization(read: [.sleepAnalysis], write: [])
        } catch {
            update { $0.onboarding.permissionStatus = .denied }
            return
        }
        update {
            $0.onboarding.permissionStatus = .granted
            $0.healthChoices.readSleep = true
        }
        await importHealth(days: HealthImport.onboardingImportDays, failurePrefix: "Health import failed.")
    }

    func completeOnboarding() {
        tick()
        update { $0.completeOnboarding(now: now) }
    }

    func advanceWalkthrough() {
        update { $0.advanceWalkthrough() }
    }

    func completeWalkthrough() {
        update { $0.completeWalkthrough() }
    }

    var colorScheme: ColorScheme? {
        switch state.appearanceMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
