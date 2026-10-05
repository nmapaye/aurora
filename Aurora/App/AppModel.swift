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

    init(
        clock: LocalClock = .current,
        text: DateText = .current,
        health: HealthKitService = HealthKitService(),
        reminders: ReminderService = ReminderService(),
        makeStore: @escaping () throws -> StateStore = StateStore.live,
        legacy: @escaping () -> LegacyImport? = LegacyImport.live
    ) {
        self.clock = clock
        self.text = text
        self.health = health
        self.reminders = reminders
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
            if let saved = store.load() {
                state = saved
            } else if let legacy = legacy() {
                switch legacy.read(now: now) {
                case .imported(let imported):
                    state = imported
                    try store.save(state)
                    legacy.removeLegacyStore()
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

    private func update(_ change: (inout AppState) -> Void) {
        change(&state)
        persist()
    }

    private func persist() {
        guard let store else { return }
        try? store.save(state)
    }

    // MARK: Caffeine

    /// Quick Add. A second tap within a second is ignored as a double tap.
    func quickAdd(_ preset: CaffeinePreset) -> Dose? {
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

    func deleteAllData() {
        update { $0.deleteAllData() }
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
