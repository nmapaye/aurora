import Foundation

/// A what-if model for a bedtime and threshold the person enters. Aurora
/// never proposes a bedtime, threshold, amount or time: every input starts
/// empty, and the half-life is the person's own Settings value, labeled as
/// an assumption. Decay uses `Caffeine.activeMg` on absolute instants, so a
/// daylight-saving change between a drink and bedtime counts real hours.
public enum CutoffScenario {
    public static let modelVersion = "cutoff-scenario-1"
    public static let assumption = "Modeled with your half-life setting. An assumption, not measured."
    public static let disclaimer = "A scenario you define. Not a recommendation or a safety limit."

    // MARK: Local times

    /// A wall-clock time the person chose, in the scenario's time zone.
    public struct LocalTime: Codable, Equatable, Hashable, Sendable {
        public var year: Int, month: Int, day: Int, hour: Int, minute: Int
        public init(year: Int, month: Int, day: Int, hour: Int, minute: Int) {
            self.year = year; self.month = month; self.day = day; self.hour = hour; self.minute = minute
        }

        /// The wall time at `ms` in `timeZone`, to the minute.
        public init(_ ms: Millis, timeZone: TimeZone) {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: ms / 1000))
            self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1, hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        }

        /// The same numbers read as UTC; nil for a date that doesn't exist (Feb 30).
        var wallMillis: Millis? {
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
            guard let date = utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) else { return nil }
            let back = utc.dateComponents([.year, .month, .day], from: date)
            guard back.year == year, back.month == month, back.day == day else { return nil }
            return date.timeIntervalSince1970 * 1000
        }
    }

    /// Which occurrence of a repeated wall time (clocks set back) is meant.
    public enum Occurrence: String, Codable, CaseIterable, Sendable { case first, second }

    public enum Resolution: Equatable, Sendable {
        case exact(Millis)
        /// The wall time happens twice; the person chooses which.
        case repeated(first: Millis, second: Millis)
        /// Clocks skip this wall time; nothing is shifted automatically.
        case skipped
        case invalid
    }

    /// Every instant whose wall time in `timeZone` is `local`.
    public static func resolve(_ local: LocalTime, in timeZone: TimeZone) -> Resolution {
        guard let wall = local.wallMillis else { return .invalid }
        // Offsets in force around that wall time; a zone changes at most once
        // within a couple of days.
        let offsets = Set([-26 * hourMs, 0, 26 * hourMs].map {
            timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: (wall + $0) / 1000))
        })
        let instants = offsets.map { wall - Millis($0) * 1000 }
            .filter { timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: $0 / 1000)) * 1000 == Int(wall - $0) }
            .sorted()
        switch instants.count {
        case 0: return .skipped
        case 1: return .exact(instants[0])
        default: return .repeated(first: instants[0], second: instants[instants.count - 1])
        }
    }

    // MARK: Input and result

    /// Editable fields. Amounts are the text typed, so an empty field stays
    /// empty instead of becoming a default.
    public struct Input: Codable, Equatable, Sendable {
        public var bedtime: LocalTime?
        public var bedtimeOccurrence: Occurrence?
        public var thresholdMg: String
        public var drinkMg: String
        public var drinkTime: LocalTime?
        public var drinkOccurrence: Occurrence?
        public init(bedtime: LocalTime? = nil, bedtimeOccurrence: Occurrence? = nil, thresholdMg: String = "", drinkMg: String = "", drinkTime: LocalTime? = nil, drinkOccurrence: Occurrence? = nil) {
            self.bedtime = bedtime; self.bedtimeOccurrence = bedtimeOccurrence; self.thresholdMg = thresholdMg
            self.drinkMg = drinkMg; self.drinkTime = drinkTime; self.drinkOccurrence = drinkOccurrence
        }
    }

    public enum Problem: String, Codable, CaseIterable, Sendable {
        case missingBedtime, bedtimeRepeated, bedtimeSkipped, bedtimeInvalid, bedtimeNotAfterCapture
        case missingThreshold, invalidThreshold
        case invalidAmount
        case drinkTimeRepeated, drinkTimeSkipped, drinkTimeInvalid, drinkTimeBeforeCapture, drinkTimeAfterBedtime
        case invalidHalfLife

        /// Inputs not entered yet, as opposed to entered values that can't be used.
        public var isMissing: Bool { [.missingBedtime, .missingThreshold, .bedtimeRepeated, .drinkTimeRepeated].contains(self) }

        public func message(timeZone: String) -> String {
            switch self {
            case .missingBedtime: "Enter a bedtime for this scenario."
            case .bedtimeRepeated: "That bedtime happens twice when clocks go back in \(timeZone). Choose which one."
            case .bedtimeSkipped: "That bedtime doesn’t exist in \(timeZone): clocks skip it. Choose another time."
            case .bedtimeInvalid: "That bedtime isn’t a valid date."
            case .bedtimeNotAfterCapture: "The bedtime has to be later than now."
            case .missingThreshold: "Enter a threshold in mg for bedtime."
            case .invalidThreshold: "The threshold must be a number of mg, 0 or more."
            case .invalidAmount: "The hypothetical amount must be a number of mg above 0."
            case .drinkTimeRepeated: "That drink time happens twice when clocks go back in \(timeZone). Choose which one."
            case .drinkTimeSkipped: "That drink time doesn’t exist in \(timeZone): clocks skip it. Choose another time."
            case .drinkTimeInvalid: "That drink time isn’t a valid date."
            case .drinkTimeBeforeCapture: "A hypothetical drink has to be later than now. Record past drinks with Log caffeine."
            case .drinkTimeAfterBedtime: "The hypothetical drink has to be at or before bedtime."
            case .invalidHalfLife: "Your caffeine half-life setting can’t be used: it must be a number of hours above 0. Change Caffeine half-life in Settings."
            }
        }
    }

    /// Modeled caffeine at bedtime from records known at capture, with
    /// Sample Data kept apart from recorded entries.
    public struct Existing: Codable, Equatable, Sendable {
        public var recordedMg: Double
        public var sampleMg: Double
        public var recordedCount: Int
        public var sampleCount: Int
        /// Entries dated after capture: never used, only counted.
        public var excludedFutureCount: Int
        public var totalMg: Double { recordedMg + sampleMg }
        public var includesSample: Bool { sampleCount > 0 }
    }

    public enum Latest: Codable, Equatable, Sendable {
        /// Required inputs are missing or invalid.
        case unavailable
        /// No hypothetical amount entered; nothing to time.
        case needsAmount
        /// The latest time the hypothetical keeps bedtime at or under the threshold.
        case feasible(Millis)
        /// That latest time is already before capture.
        case passed(Millis)
        /// Existing records alone are at or above the threshold at bedtime.
        case thresholdReachedByRecords
        /// A 0 mg threshold with caffeine to model: it never decays to 0 mg
        /// in finite time.
        case unreachable
    }

    public struct Result: Codable, Equatable, Sendable {
        public var problems: [Problem]
        public var bedtime: Millis?
        public var thresholdMg: Double?
        public var existing: Existing?
        public var amountMg: Double?
        public var drinkAt: Millis?
        /// The hypothetical drink's modeled contribution at bedtime.
        public var hypotheticalMg: Double?
        /// Existing plus hypothetical, when a drink time is entered.
        public var combinedMg: Double?
        public var latest: Latest
        /// Every known entry used, as `id|time|mg`, so a later Save can tell
        /// whether records changed.
        public var basis: [String]
    }

    /// One frozen evaluation: its inputs, assumptions, capture time and zone.
    public struct Snapshot: Codable, Equatable, Sendable {
        public var modelVersion: String
        public var capturedAt: Millis
        public var timeZone: String
        public var halfLifeHours: Double
        public var input: Input
        public var result: Result
        /// What happened to the one-off reminder last saved from this snapshot.
        public var reminder: ReminderOutcome?
    }

    public enum ReminderOutcome: Codable, Equatable, Sendable {
        case scheduled(fireAt: Millis, savedAt: Millis)
        case notAllowed
        case failed
        /// Records, inputs, time or zone changed after the preview.
        case needsNewPreview
    }

    /// The Settings value as stored, and what's wrong with it, if anything.
    /// Shown beside the assumption, never as a missing input.
    public static func halfLifeProblem(_ halfLifeHours: Double) -> String? {
        guard !(halfLifeHours.isFinite && halfLifeHours > 0) else { return nil }
        let stored = halfLifeHours.isFinite ? "\(numberText(halfLifeHours))h" : "not a number"
        return "Saved value: \(stored). " + Problem.invalidHalfLife.message(timeZone: "")
    }

    /// Why there's no latest time, pointing at the actual cause.
    public static func latestUnavailableText(_ problems: [Problem]) -> String {
        if problems.contains(.invalidHalfLife) { return Problem.invalidHalfLife.message(timeZone: "") }
        if problems.contains(.invalidAmount) { return Problem.invalidAmount.message(timeZone: "") }
        return "Enter a bedtime and a threshold, then Calculate."
    }

    /// An entered quantity as typed, never rounded away ("0.4 mg").
    public static func enteredMg(_ value: Double) -> String { "\(numberText(value)) mg" }

    // MARK: Evaluation

    public static func evaluate(input: Input, doses: [Dose], halfLifeHours: Double, now: Millis, timeZone: TimeZone) -> Snapshot {
        var problems: [Problem] = []
        let halfLifeValid = halfLifeHours.isFinite && halfLifeHours > 0
        if !halfLifeValid { problems.append(.invalidHalfLife) }

        func instant(_ local: LocalTime?, _ occurrence: Occurrence?, missing: Problem?, repeated: Problem, skipped: Problem, invalid: Problem) -> Millis? {
            guard let local else { if let missing { problems.append(missing) }; return nil }
            switch resolve(local, in: timeZone) {
            case .exact(let ms): return ms
            case .repeated(let first, let second):
                guard let occurrence else { problems.append(repeated); return nil }
                return occurrence == .first ? first : second
            case .skipped: problems.append(skipped); return nil
            case .invalid: problems.append(invalid); return nil
            }
        }

        var bedtime = instant(input.bedtime, input.bedtimeOccurrence, missing: .missingBedtime, repeated: .bedtimeRepeated, skipped: .bedtimeSkipped, invalid: .bedtimeInvalid)
        if let value = bedtime, value <= now { problems.append(.bedtimeNotAfterCapture); bedtime = nil }

        let threshold = number(input.thresholdMg)
        if input.thresholdMg.trimmingCharacters(in: .whitespaces).isEmpty { problems.append(.missingThreshold) }
        else if threshold == nil || threshold! < 0 { problems.append(.invalidThreshold) }
        let thresholdMg = threshold.flatMap { $0 >= 0 ? $0 : nil }

        let amountText = input.drinkMg.trimmingCharacters(in: .whitespaces)
        let amount = number(amountText)
        if !amountText.isEmpty && (amount == nil || amount! <= 0) { problems.append(.invalidAmount) }
        let amountMg = amount.flatMap { $0 > 0 ? $0 : nil }

        var drinkAt = instant(input.drinkTime, input.drinkOccurrence, missing: nil, repeated: .drinkTimeRepeated, skipped: .drinkTimeSkipped, invalid: .drinkTimeInvalid)
        if let value = drinkAt {
            if value < now { problems.append(.drinkTimeBeforeCapture); drinkAt = nil }
            else if let bedtime, value > bedtime { problems.append(.drinkTimeAfterBedtime); drinkAt = nil }
        }

        // Known at capture only: future-dated entries are never used.
        let known = doses.filter { $0.timestamp <= now }
        let basis = known.map { "\($0.id)|\(Int64($0.timestamp))|\($0.mg)" }.sorted()
        var existing: Existing?
        if let bedtime, halfLifeValid {
            let recorded = known.filter { !RecordID.isSample($0.id) }
            let sample = known.filter { RecordID.isSample($0.id) }
            existing = Existing(
                recordedMg: Caffeine.activeMg(at: bedtime, doses: recorded, halfLifeHours: halfLifeHours),
                sampleMg: Caffeine.activeMg(at: bedtime, doses: sample, halfLifeHours: halfLifeHours),
                recordedCount: recorded.count, sampleCount: sample.count,
                excludedFutureCount: doses.count - known.count
            )
        }

        var hypothetical: Double?
        if let bedtime, let amountMg, let drinkAt, halfLifeValid {
            hypothetical = Caffeine.activeMg(at: bedtime, doses: [Dose(id: "scenario", timestamp: drinkAt, mg: amountMg)], halfLifeHours: halfLifeHours)
        }
        let combined = existing.flatMap { e in hypothetical.map { e.totalMg + $0 } }

        let latest: Latest
        if let bedtime, let thresholdMg, let existing, problems.allSatisfy({ !$0.blocksLatest }) {
            latest = latestTime(bedtime: bedtime, thresholdMg: thresholdMg, existingMg: existing.totalMg, amountMg: amountMg, halfLifeHours: halfLifeHours, now: now)
        } else {
            latest = .unavailable
        }

        let result = Result(problems: problems, bedtime: bedtime, thresholdMg: thresholdMg, existing: existing, amountMg: amountMg,
                            drinkAt: drinkAt, hypotheticalMg: hypothetical, combinedMg: combined, latest: latest, basis: basis)
        return Snapshot(modelVersion: modelVersion, capturedAt: now, timeZone: timeZone.identifier, halfLifeHours: halfLifeHours, input: input, result: result)
    }

    /// Solves `existing + amount · 0.5^(h / halfLife) ≤ threshold` for the
    /// smallest `h` hours before bedtime, rounded to an earlier whole minute so
    /// the condition still holds at the time shown.
    static func latestTime(bedtime: Millis, thresholdMg: Double, existingMg: Double, amountMg: Double?, halfLifeHours: Double, now: Millis) -> Latest {
        // Modeled caffeine halves but never reaches 0 mg in finite time.
        if thresholdMg == 0 && existingMg > 0 { return .unreachable }
        if existingMg > 0 && existingMg >= thresholdMg { return .thresholdReachedByRecords }
        guard let amountMg else { return .needsAmount }
        let headroom = thresholdMg - existingMg
        guard headroom > 0 else { return .unreachable }
        let hoursBefore = amountMg <= headroom ? 0 : halfLifeHours * log2(amountMg / headroom)
        let raw = bedtime - hoursBefore * hourMs
        guard raw.isFinite else { return .unreachable }
        let time = (raw / minuteMs).rounded(.down) * minuteMs
        return time < now ? .passed(time) : .feasible(time)
    }

    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }

    // MARK: Reminder

    public struct ReminderContent: Equatable, Sendable {
        public var title: String
        public var body: String
        public var fireAt: Millis
        public init(title: String, body: String, fireAt: Millis) { self.title = title; self.body = body; self.fireAt = fireAt }
    }

    public static let reminderIdentifier = "cutoff-scenario-reminder"

    /// The one-off reminder for a snapshot's latest time, or nil when that
    /// time isn't a valid future instant.
    public static func reminder(for snapshot: Snapshot, now: Millis, text: DateText) -> ReminderContent? {
        guard case .feasible(let time) = snapshot.result.latest, time > now,
              let bedtime = snapshot.result.bedtime, let threshold = snapshot.result.thresholdMg, let amount = snapshot.result.amountMg else { return nil }
        return ReminderContent(
            title: "Your cutoff scenario",
            body: "The latest time in your scenario for \(enteredMg(amount)), with \(enteredMg(threshold)) at \(text.clockTime(bedtime)) bedtime. A user-defined scenario, not a safety limit.",
            fireAt: time
        )
    }

    public enum Revalidation: Equatable, Sendable {
        case current(ReminderContent)
        case changed(String)
    }

    /// Before a reminder is saved: the preview's snapshot must still be what
    /// current records, inputs, settings, zone and time give.
    public static func revalidate(_ preview: Snapshot, input: Input, doses: [Dose], halfLifeHours: Double, now: Millis, timeZone: TimeZone, text: DateText) -> Revalidation {
        if timeZone.identifier != preview.timeZone { return .changed("Your time zone changed. Start a new scenario.") }
        if input != preview.input { return .changed("The inputs changed. Calculate and preview again.") }
        if halfLifeHours != preview.halfLifeHours { return .changed("Your half-life setting changed. Calculate and preview again.") }
        let current = evaluate(input: input, doses: doses, halfLifeHours: halfLifeHours, now: now, timeZone: timeZone)
        if current.result.basis != preview.result.basis { return .changed("Your caffeine records changed. Calculate and preview again.") }
        guard current.result.latest == preview.result.latest, let content = reminder(for: current, now: now, text: text) else {
            return .changed("That time has passed or the result changed. Calculate and preview again.")
        }
        return .current(content)
    }
}

private extension CutoffScenario.Problem {
    /// The latest time needs bedtime, threshold and half-life; a drink time
    /// problem leaves it computable, a bad amount doesn't.
    var blocksLatest: Bool {
        ![.drinkTimeRepeated, .drinkTimeSkipped, .drinkTimeInvalid, .drinkTimeBeforeCapture, .drinkTimeAfterBedtime].contains(self)
    }
}
