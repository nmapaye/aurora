import Foundation

/// Only application code builds these finite native experiences. The local
/// classifier chooses an intent; it never supplies UI, metrics, or actions.
public struct AssistantCard: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case caffeineDraft, sleepDraft, energy, trends, calendar, reaction, history, exports, briefing, reminders, clarification, receipt
    }
    public enum State: String, Codable, Sendable { case ready, loading, saved, undone, expired, failed, discarded }
    public struct Metric: Codable, Equatable, Identifiable, Sendable {
        public var id: String; public var label: String; public var value: String
        public var source: String; public var detail: String; public var missing: Bool
        public init(id: String, label: String, value: String, source: String, detail: String = "", missing: Bool = false) {
            self.id = id; self.label = label; self.value = value; self.source = source; self.detail = detail; self.missing = missing
        }
    }
    public struct Point: Codable, Equatable, Identifiable, Sendable {
        public var date: Millis; public var value: Double?; public var detail: String; public var sample: Bool
        public var id: Millis { date }
    }
    public struct Series: Codable, Equatable, Identifiable, Sendable {
        public var metric: String; public var days: Int; public var unit: String
        public var summary: String; public var comparison: String; public var points: [Point]
        public var id: String { "\(metric):\(days)" }
    }
    public struct Record: Codable, Equatable, Identifiable, Sendable {
        public var id: String; public var kind: String; public var title: String
        public var date: Millis; public var source: String; public var detail: String; public var editable: Bool
        public var revision: String = ""
        public var identity: String { "\(kind):\(id)" }
    }
    public var kind: Kind
    public var state: State = .ready
    public var capturedAt: Millis
    public var timeZone: String = TimeZone.current.identifier
    public var title: String
    public var summary: String
    public var metrics: [Metric] = []
    public var series: [Series] = []
    public var records: [Record] = []
    public var commitments: [Commitment] = []
    public var recordID: String?
    public var recordKind: String?
    public init(kind: Kind, capturedAt: Millis, title: String, summary: String = "") {
        self.kind = kind; self.capturedAt = capturedAt; self.title = title; self.summary = summary
    }
    public var refreshIntent: AssistantIntent? {
        switch kind {
        case .caffeineDraft: .logCaffeine
        case .sleepDraft: .logSleep
        case .energy: .explainEnergy
        case .trends: .weeklyTrends
        case .calendar: .calendar
        case .reaction: .reactionTest
        case .history: .history
        case .exports: .exports
        case .briefing: .briefing
        case .reminders: .reminders
        case .clarification, .receipt: nil
        }
    }
}

public enum AssistantCards {
    public static func make(_ kind: AssistantCard.Kind, state: AppState, now: Millis, clock: LocalClock, text: DateText) -> AssistantCard {
        let title: String = switch kind {
        case .caffeineDraft: "Record caffeine"
        case .sleepDraft: "Record sleep"
        case .energy: "Your energy signals"
        case .trends: "Recorded trends"
        case .calendar: "Your commitments"
        case .reaction: "Reaction Test"
        case .history: "Your recorded history"
        case .exports: "Export your records"
        case .briefing: "Your recorded day"
        case .reminders: "Your reminders"
        case .clarification: "What would you like to do?"
        case .receipt: "Saved"
        }
        var card = AssistantCard(kind: kind, capturedAt: now, title: title)
        card.timeZone = clock.timeZone.identifier
        switch kind {
        case .energy, .briefing:
            let estimate = Summary.estimateAlertness(at: now, doses: state.doses, sleeps: state.sleeps, inputs: .init(prefs: state.prefs, clock: clock))
            let today = state.doses.filter { $0.timestamp >= clock.startOfDay(now) && $0.timestamp <= now }
            let hours = SleepDebt.totalHoursLast24(at: now, sleeps: state.sleeps)
            let sleepIDs = state.sleeps.filter { $0.end > now - dayMs && $0.start <= now }.map(\.id)
            card.metrics = [
                .init(id: "sleep", label: "Sleep · last 24 hours", value: hours > 0 ? formatSleepHours(hours) : "No record", source: sleepIDs.contains(where: RecordID.isSample) ? "Includes Sample Data" : sleepIDs.map { SleepModel.sourceLabel(id: $0) }.uniqued().joined(separator: " · "), missing: hours <= 0),
                .init(id: "caffeine", label: "Caffeine · today", value: today.isEmpty ? "No record" : "\(numberText(today.reduce(0) { $0 + $1.mg })) mg", source: RecordSource.of(ids: today.map(\.id))?.rawValue ?? "Recorded entries", missing: today.isEmpty),
                .init(id: "alertness", label: "Estimated alertness", value: estimate.score.map { "\($0) / 100" } ?? "Unavailable", source: "Estimate", detail: Summary.describe(estimate), missing: estimate.score == nil)
            ]
            card.summary = "These records cannot establish why you feel tired. Stress, illness, and other factors aren't measured here."
        case .trends:
            for days in [7, 30] {
                let p = Insights.presentation(doses: state.doses, vigilanceSessions: state.vigilanceSessions, range: days == 7 ? .week : .month, now: now, clock: clock, text: text)
                card.series.append(.init(metric: "Caffeine", days: days, unit: "mg", summary: p.accessibilitySummary, comparison: p.trend.text, points: p.points.map { point in
                    let r = Insights.describeChartDay(point, text: text)
                    return .init(date: point.date, value: point.mg.map(Double.init), detail: r.value, sample: point.source == .sample || point.source == .mixed)
                }))
                let sleep = SleepModel.presentation(sessions: state.sleeps, targetSleepHours: state.prefs.targetSleep, range: days == 7 ? .week : .month, now: now, clock: clock, text: text)
                card.series.append(.init(metric: "Sleep", days: days, unit: "h", summary: sleep.accessibilitySummary, comparison: "Averages include recorded days only.", points: sleep.points.map { point in
                    let sources = state.sleeps.filter { clock.dayKey($0.end) == clock.dayKey(point.date) }
                    return .init(date: point.date, value: point.durationMs.map { $0 / hourMs }, detail: point.durationMs.map { formatHoursMinutes(durationMs: $0) } ?? "No record", sample: sources.contains { RecordID.isSample($0.id) })
                }))
                let signal = Insights.reactionSignal(sessions: state.vigilanceSessions, now: now, clock: clock, text: text)
                card.series.append(.init(metric: "Reaction", days: days, unit: "score", summary: signal.signal.accessibilityDescription, comparison: signal.signal.context, points: clock.dayStarts(endingAt: now, days: days).map { date in
                    let latest = state.vigilanceSessions.filter { clock.dayKey($0.completedAt) == clock.dayKey(date) && $0.completedAt <= now }.max { $0.completedAt < $1.completedAt }
                    return .init(date: date, value: latest.map { Double($0.score) }, detail: latest.map { "\($0.score) · \($0.rating.rawValue)" } ?? "No record", sample: latest.map { RecordID.isSample($0.id) } ?? false)
                }))
            }
        case .reaction:
            let r = Insights.reactionSignal(sessions: state.vigilanceSessions, now: now, clock: clock, text: text)
            card.summary = "A 60-second test of reaction speed. Sit somewhere you can focus before starting."
            card.metrics = [.init(id: "reaction", label: "Latest recorded test", value: r.signal.value ?? "No record", source: r.signal.metaLine, detail: r.signal.context, missing: r.signal.status == .empty)]
        case .history:
            card.records = state.doses.filter { $0.timestamp <= now }.map {
                .init(id: $0.id, kind: "caffeine", title: $0.source ?? "Caffeine", date: $0.timestamp, source: CaffeineLog.sourceLabel($0), detail: "\(numberText($0.mg)) mg", editable: CaffeineLog.isEditable($0), revision: "\($0.timestamp)|\($0.mg)|\($0.source ?? "")|\($0.note ?? "")")
            } + state.sleeps.filter { $0.end <= now }.map {
                .init(id: $0.id, kind: "sleep", title: $0.type == .nap ? "Nap" : "Sleep", date: $0.end, source: SleepModel.sourceLabel(id: $0.id), detail: "\(text.clockTime($0.start)) – \(text.clockTime($0.end)) · \(formatHoursMinutes(durationMs: $0.end - $0.start))", editable: RecordID.isManualSleep($0.id), revision: "\($0.start)|\($0.end)|\($0.type.rawValue)|\($0.note ?? "")")
            } + state.vigilanceSessions.filter { $0.completedAt <= now }.map {
                .init(id: $0.id, kind: "reaction", title: "Reaction Test", date: $0.completedAt, source: RecordID.isSample($0.id) ? "Sample Data" : "Recorded", detail: "\($0.score) · \($0.rating.rawValue)", editable: false)
            }
            card.records.sort { $0.date > $1.date }
        case .exports:
            card.summary = "Share a CSV of the current records. Sources and missing days remain labeled."
        case .reminders:
            card.summary = "Reminders use times you choose. Proactive suggestions are opt-in; quiet hours and daily limits still apply."
        case .caffeineDraft: card.summary = "Review the amount, source, and local time before saving."
        case .sleepDraft: card.summary = "Choose the local start and end. These are editable placeholders, not a sleep recommendation."
        case .calendar: card.summary = "Nothing changes until you approve a preview."
        case .clarification: card.summary = "Choose one task, or tell me a little more. I won’t prescribe doses or sleep schedules."
        case .receipt: break
        }
        return card
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}
