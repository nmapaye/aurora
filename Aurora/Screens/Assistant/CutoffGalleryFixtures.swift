#if DEBUG
import AuroraCore
import Foundation

/// Cutoff scenario states for the Design Gallery, from made-up records in
/// the gallery's temporary folder. Reminder saves use the fixture's own
/// outcome and never reach the notification center or ask for permission.
enum CutoffFixture: String, CaseIterable, Identifiable {
    case empty = "Empty inputs"
    case feasible = "Time ahead"
    case noAmount = "No hypothetical"
    case passed = "Time passed"
    case reached = "Records at threshold"
    case unreachable = "Zero threshold"
    case invalid = "Invalid inputs"
    case sample = "Sample Data"
    case repeated = "Repeated local time"
    case skipped = "Skipped local time"
    case preview = "Reminder preview"
    case notAllowed = "Notifications off"
    case saveFails = "Save fails"
    case scheduled = "Saved (fixture)"
    case earlier = "Earlier snapshot"
    var id: String { rawValue }

    @MainActor func show(app: AppModel, assistant: AssistantModel) async {
        app.deleteAllData()
        let now = AppModel.currentMillis()
        let zone = app.clock.timeZone
        func local(_ ms: Millis) -> CutoffScenario.LocalTime { .init(ms, timeZone: zone) }
        func dose(_ mg: String, hoursAgo: Double) { _ = app.addCustomDose(.init(mg: mg, source: "Drip", timestamp: now - hoursAgo * hourMs, note: "Synthetic fixture")) }
        let bedtime = local(now + 10 * hourMs)
        var input = CutoffScenario.Input(bedtime: bedtime, thresholdMg: "50", drinkMg: "95", drinkTime: local(now + 2 * hourMs))
        assistant.scheduleCutoffReminder = { _ in
            switch self {
            case .scheduled: .scheduled
            case .saveFails: .failed
            default: .notAllowed
            }
        }
        switch self {
        case .empty: input = .init()
        case .feasible, .preview, .notAllowed, .saveFails, .scheduled, .earlier: dose("95", hoursAgo: 3)
        case .noAmount: dose("95", hoursAgo: 3); input.drinkMg = ""; input.drinkTime = nil
        case .passed: input.drinkMg = "400"; input.drinkTime = nil; input.bedtime = local(now + 2 * hourMs)
        case .reached: dose("400", hoursAgo: 1)
        case .unreachable: dose("60", hoursAgo: 2); input.thresholdMg = "0"
        case .invalid: input.thresholdMg = "-5"; input.drinkMg = "0"
        case .sample: app.loadSampleData(); dose("60", hoursAgo: 2)
        case .repeated: input = .init(bedtime: Self.clockChange(after: now, zone: zone, repeated: true), thresholdMg: "50")
        case .skipped: input = .init(bedtime: Self.clockChange(after: now, zone: zone, repeated: false), thresholdMg: "50")
        }
        app.tick()
        if self == .earlier {
            // Captured three hours earlier: a closed snapshot with its own result.
            let card = AssistantCards.cutoffScenario(input: input, state: app.state, now: app.now - 3 * hourMs, clock: app.clock, text: app.text)
            assistant.conversation.messages.append(.init(text: card.title, card: card))
            return
        }
        assistant.openCutoff(input: input, app: app)
        if self != .empty { assistant.calculateCutoff(app: app) }
        if [.preview, .notAllowed, .saveFails, .scheduled].contains(self) { assistant.previewCutoffReminder(app: app) }
        if [.notAllowed, .saveFails, .scheduled].contains(self) { await assistant.saveCutoffReminder(app: app) }
    }

    /// A wall time that the zone's next clock change repeats or skips, or
    /// nil (left for the person to add) in a zone without one.
    static func clockChange(after now: Millis, zone: TimeZone, repeated: Bool) -> CutoffScenario.LocalTime? {
        var from = Date(timeIntervalSince1970: now / 1000)
        for _ in 0..<4 {
            guard let change = zone.nextDaylightSavingTimeTransition(after: from) else { return nil }
            let at = change.timeIntervalSince1970 * 1000
            let before = Millis(zone.secondsFromGMT(for: change.addingTimeInterval(-1))) * 1000
            let after = Millis(zone.secondsFromGMT(for: change)) * 1000
            // Fifteen minutes into the overlap, or into the gap: the wall
            // time just before the change moved by the shift, read at the old offset.
            let oldOffset = TimeZone(secondsFromGMT: Int(before / 1000)) ?? zone
            let candidate = repeated
                ? CutoffScenario.LocalTime(at + 15 * minuteMs, timeZone: zone)
                : CutoffScenario.LocalTime(at - 15 * minuteMs + (after - before), timeZone: oldOffset)
            let resolution = CutoffScenario.resolve(candidate, in: zone)
            if repeated, case .repeated = resolution { return candidate }
            if !repeated, resolution == .skipped { return candidate }
            from = change.addingTimeInterval(60)
        }
        return nil
    }
}
#endif
