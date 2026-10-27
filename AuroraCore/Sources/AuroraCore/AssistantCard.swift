import Foundation

/// Only application code builds these finite native experiences. The local
/// classifier chooses an intent; it never supplies UI, metrics, or actions.
public struct AssistantCard: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case caffeineDraft, sleepDraft, energy, trends, calendar, reaction, history, exports, briefing, reminders, clarification, receipt
        case energyProjection, energyCheckIn
        case cutoffScenario
        /// Everything Aurora can do, by group.
        case capabilities
        /// A next-day follow-up on yesterday's drink.
        case repeatDrink
        /// A new conversation's first card: one line and three starting
        /// points. The full list stays one "What can you do?" away.
        case welcome
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
    /// Energy evidence captured with the card. Optional so older saved
    /// conversations decode unchanged.
    public var energy: EnergySnapshot?
    /// A check-in review's recent ratings, or a check-in receipt.
    public var checkIn: CheckIn?
    /// A cutoff scenario's latest calculation. Optional so older saved
    /// conversations decode unchanged.
    public var cutoff: CutoffScenario.Snapshot?
    /// A next-day follow-up's drink. Optional so older saved conversations
    /// decode unchanged.
    public var repeatDrink: RepeatDrinks.Prompt?
    public struct CheckIn: Codable, Equatable, Sendable {
        /// Receipt: the check-in as saved.
        public var saved: EnergyCheckIn?
        /// Receipt of a correction: the check-in before it.
        public var previous: EnergyCheckIn?
        /// Ratings from the 7 days before capture, newest first.
        public var recent: [EnergyCheckIn]
        public init(saved: EnergyCheckIn? = nil, previous: EnergyCheckIn? = nil, recent: [EnergyCheckIn] = []) {
            self.saved = saved; self.previous = previous; self.recent = recent
        }
    }
    public init(kind: Kind, capturedAt: Millis, title: String, summary: String = "") {
        self.kind = kind; self.capturedAt = capturedAt; self.title = title; self.summary = summary
    }
    public var refreshIntent: AssistantIntent? {
        switch kind {
        case .caffeineDraft: .logCaffeine
        case .sleepDraft: .logSleep
        case .energy: .explainEnergy
        case .energyProjection: .energyProjection
        case .energyCheckIn: .energyCheckIn
        case .cutoffScenario: .cutoffScenario
        case .trends: .weeklyTrends
        case .calendar: .calendar
        case .reaction: .reactionTest
        case .history: .history
        case .exports: .exports
        case .briefing: .briefing
        case .reminders: .reminders
        case .capabilities: .help
        case .clarification, .receipt, .repeatDrink, .welcome: nil
        }
    }
}

public enum AssistantCards {
    public static func make(_ kind: AssistantCard.Kind, state: AppState, now: Millis, clock: LocalClock, text: DateText) -> AssistantCard {
        let title: String = switch kind {
        case .caffeineDraft: "Record caffeine"
        case .sleepDraft: "Record sleep"
        case .energy: "Your energy signals"
        case .energyProjection: "Modeled alertness · 24 hours"
        case .energyCheckIn: "Energy check-in"
        case .cutoffScenario: "Cutoff scenario"
        case .trends: "Recorded trends"
        case .calendar: "Your commitments"
        case .reaction: "Reaction Test"
        case .history: "Your recorded history"
        case .exports: "Export your records"
        case .briefing: "Your recorded day"
        case .reminders: "Your reminders"
        case .clarification: "What would you like to do?"
        case .receipt: "Saved"
        case .capabilities: "What Aurora can do"
        case .repeatDrink: "Yesterday’s drink"
        case .welcome: "Ready when you are."
        }
        var card = AssistantCard(kind: kind, capturedAt: now, title: title)
        card.timeZone = clock.timeZone.identifier
        switch kind {
        case .energy, .briefing:
            // One known-at-capture input set for every metric, the snapshot
            // and the curve: nothing dated after capture, no unfinished sleep.
            let known = EnergyProjection.knownRecords(doses: state.doses, sleeps: state.sleeps, at: now)
            let estimate = Summary.estimateAlertness(at: now, doses: known.doses, sleeps: known.sleeps, inputs: .init(prefs: state.prefs, clock: clock))
            let today = known.doses.filter { $0.timestamp >= clock.startOfDay(now) }
            let hours = SleepDebt.totalHoursLast24(at: now, sleeps: known.sleeps)
            let sleepIDs = known.sleeps.filter { $0.end > now - dayMs }.map(\.id)
            card.metrics = [
                .init(id: "sleep", label: "Sleep · last 24 hours", value: hours > 0 ? formatSleepHours(hours) : "No record", source: sleepIDs.contains(where: RecordID.isSample) ? "Includes Sample Data" : sleepIDs.map { SleepModel.sourceLabel(id: $0) }.uniqued().joined(separator: " · "), missing: hours <= 0),
                .init(id: "caffeine", label: "Caffeine · today", value: today.isEmpty ? "No record" : "\(numberText(today.reduce(0) { $0 + $1.mg })) mg", source: RecordSource.of(ids: today.map(\.id))?.rawValue ?? "Recorded entries", missing: today.isEmpty),
                // With no score, the source names the missing record instead of a scale.
                .init(id: "alertness", label: EnergyEstimate.title, value: estimate.score.map { "\($0)" } ?? "Unavailable", source: estimate.score == nil ? EnergyEstimate.missingSleepText(sleeps: known.sleeps, at: now, text: text) : EnergyEstimate.scaleLabel, detail: EnergyEstimate.capture(at: now, doses: known.doses, sleeps: known.sleeps, inputs: .init(prefs: state.prefs, clock: clock)).summary, missing: estimate.score == nil)
            ]
            card.summary = ""
            if kind == .energy {
                let snapshot = EnergySnapshot.capture(state: state, now: now, clock: clock, includeProjection: false)
                card.energy = snapshot
                let evidence = snapshot.estimate.evidence
                card.metrics.insert(.init(
                    id: "activeCaffeine", label: "Estimated active caffeine",
                    value: evidence.hasActiveCaffeine ? "\(numberText(jsRound(evidence.activeCaffeineMg))) mg" : "No record",
                    source: "Modeled with a \(numberText(snapshot.estimate.halfLifeHours))h half-life",
                    missing: !evidence.hasActiveCaffeine
                ), at: 2)
            }
        case .energyProjection:
            let snapshot = EnergySnapshot.capture(state: state, now: now, clock: clock, includeProjection: true)
            card.energy = snapshot
            card.summary = EnergyProjection.futureAssumption
            card.metrics = [.init(
                id: "alertness", label: EnergyEstimate.title + " · now",
                value: snapshot.estimate.modeledScore.map { "\($0)" } ?? "Unavailable",
                source: snapshot.estimate.modeledScore == nil
                    ? EnergyEstimate.missingSleepText(sleeps: state.sleeps, at: now, text: text) : EnergyEstimate.scaleLabel,
                detail: snapshot.estimate.summary, missing: snapshot.estimate.modeledScore == nil
            )]
        case .energyCheckIn:
            card.summary = EnergyCheckIn.kindLabel
            card.checkIn = .init(recent: state.energyCheckIns.filter { $0.recordedAt <= now && $0.recordedAt > now - 7 * dayMs }
                .sorted { ($0.recordedAt, $0.id) > ($1.recordedAt, $1.id) })
        case .trends:
            for days in [7, 30] {
                let p = Insights.presentation(doses: state.doses, vigilanceSessions: state.vigilanceSessions, range: days == 7 ? .week : .month, now: now, clock: clock, text: text)
                card.series.append(.init(metric: "Caffeine", days: days, unit: "mg", summary: p.accessibilitySummary, comparison: p.trend.text, points: p.points.map { point in
                    let r = Insights.describeChartDay(point, text: text)
                    return .init(date: point.date, value: point.mg.map(Double.init), detail: r.value, sample: point.source?.includesSample ?? false)
                }))
                let sleep = SleepModel.presentation(sessions: state.sleeps, targetSleepHours: state.prefs.targetSleep, range: days == 7 ? .week : .month, now: now, clock: clock, text: text)
                card.series.append(.init(metric: "Sleep", days: days, unit: "h", summary: sleep.accessibilitySummary, comparison: "Averages include recorded days only.", points: sleep.points.map { point in
                    let sources = state.sleeps.filter { clock.dayKey($0.end) == clock.dayKey(point.date) }
                    return .init(date: point.date, value: point.durationMs.map { $0 / hourMs }, detail: point.durationMs.map { formatHoursMinutes(durationMs: $0) } ?? "No record", sample: sources.contains { RecordID.isSample($0.id) })
                }))
                let signal = Insights.reactionSignal(sessions: state.vigilanceSessions, now: now, clock: clock, text: text)
                // Only tests from the latest test's version are plotted; a day
                // whose test came from another version names it instead.
                let plotted = state.vigilanceSessions.filter { $0.completedAt <= now }.max { $0.completedAt < $1.completedAt }?.protocolVersion
                card.series.append(.init(metric: "Reaction", days: days, unit: "score", summary: signal.signal.accessibilityDescription, comparison: signal.signal.context, points: clock.dayStarts(endingAt: now, days: days).map { date in
                    let latest = state.vigilanceSessions.filter { clock.dayKey($0.completedAt) == clock.dayKey(date) && $0.completedAt <= now }.max { $0.completedAt < $1.completedAt }
                    let comparable = latest.map { $0.protocolVersion == plotted } ?? false
                    let detail = latest.map { [$0.protocolLabel, "\($0.score) · \($0.rating.rawValue)"].compactMap { $0 }.joined(separator: " · ") } ?? "No record"
                    return .init(date: date, value: comparable ? latest.map { Double($0.score) } : nil, detail: detail, sample: latest.map { RecordID.isSample($0.id) } ?? false)
                }))
            }
        case .reaction:
            let r = Insights.reactionSignal(sessions: state.vigilanceSessions, now: now, clock: clock, text: text)
            card.summary = "A 30-second reaction test."
            card.metrics = [.init(id: "reaction", label: "Latest recorded test", value: r.signal.value ?? "No record", source: r.signal.metaLine, detail: r.signal.context, missing: r.signal.status == .empty)]
        case .history:
            card.records = state.doses.filter { $0.timestamp <= now }.map {
                .init(id: $0.id, kind: "caffeine", title: $0.source ?? "Caffeine", date: $0.timestamp, source: CaffeineLog.sourceLabel($0), detail: "\(numberText($0.mg)) mg", editable: CaffeineLog.isEditable($0), revision: "\($0.timestamp)|\($0.mg)|\($0.source ?? "")|\($0.note ?? "")")
            } + state.sleeps.filter { $0.end <= now }.map {
                .init(id: $0.id, kind: "sleep", title: $0.type == .nap ? "Nap" : "Sleep", date: $0.end, source: SleepModel.sourceLabel(id: $0.id), detail: "\(text.clockTime($0.start)) – \(text.clockTime($0.end)) · \(formatHoursMinutes(durationMs: $0.end - $0.start))", editable: RecordID.isManualSleep($0.id), revision: "\($0.start)|\($0.end)|\($0.type.rawValue)|\($0.note ?? "")")
            } + state.vigilanceSessions.filter { $0.completedAt <= now }.map {
                .init(id: $0.id, kind: "reaction", title: "Reaction Test", date: $0.completedAt, source: RecordID.isSample($0.id) ? "Sample Data" : "Recorded", detail: [$0.protocolLabel, "\($0.score) · \($0.rating.rawValue)"].compactMap { $0 }.joined(separator: " · "), editable: false)
            }
            card.records.sort { $0.date > $1.date }
        case .exports:
            card.summary = "Share your records as CSV."
        case .reminders:
            card.summary = "Reminders at times you choose."
        // The "Review before saving" badge already says it.
        case .caffeineDraft: card.summary = ""
        case .sleepDraft: card.summary = "Set when you slept."
        case .calendar: card.summary = ""
        case .clarification: card.summary = "Choose one, or tell me a little more."
        case .cutoffScenario:
            // The "Scenario" badge labels it; the disclaimer sits under Assumptions.
            card.summary = ""
            card.cutoff = CutoffScenario.evaluate(input: .init(), doses: state.doses, halfLifeHours: state.prefs.halfLife, now: now, timeZone: clock.timeZone)
        case .receipt, .welcome: break
        case .capabilities: card.summary = "Tap one, or ask in your own words."
        // Built by the follow-up itself, from the prompt it carries.
        case .repeatDrink: break
        }
        return card
    }

    /// A new cutoff scenario snapshot. Refresh carries the earlier inputs
    /// into it and calculates again from current records.
    public static func cutoffScenario(input: CutoffScenario.Input, state: AppState, now: Millis, clock: LocalClock, text: DateText) -> AssistantCard {
        var card = make(.cutoffScenario, state: state, now: now, clock: clock, text: text)
        card.cutoff = CutoffScenario.evaluate(input: input, doses: state.doses, halfLifeHours: state.prefs.halfLife, now: now, timeZone: clock.timeZone)
        return card
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}
