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
        /// Saved records couldn't be opened. Nothing is written until the
        /// person retries successfully or chooses to start fresh.
        case recovery(Recovery)
        case ready
    }

    enum Recovery: Equatable {
        /// `state.json` exists but couldn't be read; often the device is still
        /// locked. Retrying is the only option, since the records may be fine.
        case unreadable
        /// `state.json` doesn't decode. `backupKept` says a copy was made.
        case corrupt(backupKept: Bool)
        /// The React Native build's store exists but couldn't be read. It is
        /// left untouched, and the import runs again on every launch until it
        /// succeeds or the person starts fresh.
        case legacyUnreadable
        /// The old records were read but saving them failed.
        case importNotSaved

        /// Starting fresh only when the original is safe: a corrupt file must
        /// have a copy, and the old store is never touched.
        var allowsStartFresh: Bool {
            switch self {
            case .unreadable, .importNotSaved: false
            case .corrupt(let backupKept): backupKept
            case .legacyUnreadable: true
            }
        }
    }

    enum DeletionResult: Equatable {
        case completed
        /// Records were cleared, but a kept copy or export couldn't be removed.
        case incomplete
    }

    private(set) var phase: Phase = .loading
    private(set) var state = AppState()
    /// Moves every minute and on foreground, so "today" rolls over at midnight.
    private(set) var now: Millis = AppModel.currentMillis()
    /// The last save failed; the change is still on screen but not on disk.
    private(set) var saveFailed = false
    private(set) var deletionResult: DeletionResult?
    /// Start Fresh was chosen but its save failed; recovery stays up.
    private(set) var startFreshFailed = false
    private(set) var reminderStatus: ReminderService.Status = .off
    var pendingLink: DeepLink?

    let clock: LocalClock
    let text: DateText
    let health: HealthKitService
    let reminders: ReminderService
    private let makeStore: () throws -> StateStore
    private let legacy: () -> LegacyImport?
    private var store: StateStore?
    private var lastQuickAddAt: Millis?
    /// DEBUG builds only: start from an empty store for UI tests.
    private let uiTestReset: Bool

    #if DEBUG
    static let launchedForUITestReset = ProcessInfo.processInfo.arguments.contains("-AuroraUITestReset")
    #else
    static let launchedForUITestReset = false
    #endif

    init(
        clock: LocalClock = .current,
        text: DateText = .current,
        health: HealthKitService = HealthKitService(),
        reminders: ReminderService? = nil,
        makeStore: @escaping () throws -> StateStore = StateStore.live,
        legacy: @escaping () -> LegacyImport? = LegacyImport.live,
        uiTestReset: Bool = AppModel.launchedForUITestReset
    ) {
        self.uiTestReset = uiTestReset
        self.clock = clock
        self.text = text
        self.health = health
        self.reminders = reminders ?? ReminderService()
        self.makeStore = makeStore
        self.legacy = legacy
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
            tick()
            // UI tests start from an empty store. This runs before any
            // migration and never reads or removes the old store. Release
            // builds can't set it.
            if uiTestReset {
                try store.purge(includingState: true)
                state = AppState()
                phase = .ready
                return
            }
            switch store.load() {
            case .loaded(let saved):
                state = saved
                phase = .ready
            case .unreadable:
                phase = .recovery(.unreadable)
            case .corrupt(let backup):
                phase = .recovery(.corrupt(backupKept: backup != nil))
            case .missing:
                importLegacy(into: store)
            }
        } catch {
            phase = .storageUnavailable
        }
    }

    private func importLegacy(into store: StateStore) {
        switch legacy()?.read(now: now) ?? LegacyImport.Outcome.none {
        case .none:
            state = AppState()
            phase = .ready
        case .unreadable:
            phase = .recovery(.legacyUnreadable)
        case .imported(let imported):
            do {
                try store.save(imported)
                state = imported
                phase = .ready
            } catch {
                phase = .recovery(.importNotSaved)
            }
        }
    }

    func retryStorage() {
        startFreshFailed = false
        phase = .loading
        load()
    }

    /// Replaces unreadable records with an empty store, once the person
    /// confirms. The corrupt file's copy and the old store are kept.
    func startFresh() {
        guard case .recovery(let recovery) = phase, recovery.allowsStartFresh, let store else { return }
        do {
            try store.save(AppState())
            state = AppState()
            saveFailed = false
            startFreshFailed = false
            phase = .ready
        } catch {
            startFreshFailed = true
        }
    }

    private func update(_ change: (inout AppState) -> Void) {
        guard phase == .ready else { return }
        change(&state)
        persist()
    }

    private func persist() {
        guard phase == .ready, let store else { return }
        do {
            try store.save(state)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    /// Tries the failed save again with what is on screen.
    func retrySave() {
        persist()
    }

    // MARK: Caffeine

    /// Quick Add. A second tap within a second is ignored as a double tap.
    func quickAdd(_ preset: CaffeinePreset) -> Dose? {
        guard phase == .ready else { return nil }
        tick()
        guard CaffeineLog.acceptsQuickAdd(lastAcceptedAt: lastQuickAddAt, at: now) else { return nil }
        lastQuickAddAt = now
        let dose = CaffeineLog.quickAddDose(preset, now: now, id: RecordID.newDoseID(now: now))
        update { $0.addDose(dose) }
        return dose
    }

    func addCustomDose(_ draft: CustomDoseDraft) -> Dose {
        tick()
        let dose = CaffeineLog.customDose(draft, id: RecordID.newDoseID(now: now))
        update { $0.addDose(dose) }
        return dose
    }

    func correctDose(id: String, with draft: CustomDoseDraft) {
        guard let dose = state.doses.first(where: { $0.id == id }), CaffeineLog.isEditable(dose) else { return }
        update { $0.updateDose(id: id, with: CaffeineLog.patch(from: draft)) }
    }

    func deleteDose(id: String) {
        guard let dose = state.doses.first(where: { $0.id == id }), CaffeineLog.isEditable(dose) else { return }
        update { $0.removeDose(id: id) }
    }

    /// Undo for the dose Quick Add just logged.
    func undo(_ dose: Dose) {
        update { $0.removeDose(id: dose.id) }
    }

    // MARK: Sleep

    func addManualSleep(_ draft: ManualSleep.Draft) {
        tick()
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
            try await health.requestReadAccess()
        } catch {
            tick()
            update {
                $0.onboarding.source = .manual
                $0.onboarding.permissionStatus = .denied
                $0.healthSync = HealthSync(lastSyncedAt: now, lastMessage: SleepDataStatus.notSetUpMessage, importedCount: 0, importStatus: .idle)
            }
            return
        }
        update {
            $0.onboarding.source = .healthkit
            $0.onboarding.permissionStatus = .granted
        }
        await importHealth(days: importDays, failurePrefix: failurePrefix)
    }

    func importHealth(days: Double = HealthImport.refreshDays, failurePrefix: String = "Health refresh failed.") async {
        tick()
        let end = now
        update {
            $0.healthSync.importStatus = .importing
            $0.healthSync.lastMessage = HealthImport.importingMessage
        }
        do {
            let samples = try await health.sleepSamples(from: end - days * dayMs, to: end)
            tick()
            update { _ = HealthImport.apply(samples, days: days, now: end, to: &$0) }
        } catch {
            tick()
            let message = (error as? LocalizedError)?.errorDescription ?? "Unable to read sleep data."
            update { HealthImport.recordFailure(message, prefix: failurePrefix, now: self.now, to: &$0) }
        }
    }

    /// Runs whenever Aurora becomes active: keeps the reminder current and
    /// refreshes Health quietly when a refresh is due. Never prompts.
    func foregroundSync() async {
        tick()
        guard phase == .ready, state.onboarding.completed else { return }
        reminderStatus = await reminders.sync(enabled: state.prefs.notifyCutoff, cutoffHour: state.prefs.cutoffHour, prompt: false)
        if HealthImport.shouldRefresh(state: state, now: now) {
            await importHealth()
        }
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
        update { $0.loadSampleData(now: now, clock: clock) }
    }

    func clearSampleData() {
        update { $0.clearSampleData() }
    }

    /// Clears every record, then removes what Aurora kept on the side: copies
    /// of unreadable files, the React Native build's store and CSV exports.
    /// Settings asks the person to confirm first.
    func deleteAllData() {
        update { $0.deleteAllData() }
        guard phase == .ready, !saveFailed, let store else {
            deletionResult = .incomplete
            return
        }
        do {
            try store.purge(includingState: false)
            try legacy()?.purge()
            try CSVFile.purgeExports()
            deletionResult = .completed
        } catch {
            deletionResult = .incomplete
        }
    }

    // MARK: Reaction Test

    func saveReactionTest(_ session: VigilanceSession) {
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
            try await health.requestReadAccess()
        } catch {
            update { $0.onboarding.permissionStatus = .denied }
            return
        }
        update { $0.onboarding.permissionStatus = .granted }
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
