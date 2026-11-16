import Foundation

/// The follow-up chat card's state: one "how much caffeine at <time>"
/// question, the chips it still needs, and its last computed rows.
///
/// Everything here is code: times come from `CaffeineQuestion`, amounts
/// from the person or the caffeine database (#88 search), numbers from
/// `CaffeineAtTime.evaluate`. Nothing writes a dose or a Health sample;
/// "Log This Drink" only returns a draft for the existing confirm card.
public struct CaffeineAtTimeCard: Codable, Equatable, Sendable {
    /// Where a time sits in the question.
    public enum Slot: Codable, Equatable, Hashable, Sendable {
        case drink
        case target(Int)
        /// The sleep time, from the chip or the picker.
        case sleep
    }

    /// A chip. Nothing is chosen until it's tapped.
    public enum Choice: Codable, Equatable, Hashable, Sendable {
        /// Resolves a bare hour or "into 5pm".
        case time(Slot, CaffeineQuestion.TimeSpec)
        /// One of the two instants of a wall time that happens twice.
        case instant(Slot, Millis, first: Bool)
        case duplicate(CaffeineAtTime.DuplicateChoice)
        /// Uses the median of recorded nights; never `Prefs.targetSleep`.
        case sleepChip
        /// A database record from the #88 search.
        case candidate(entryID: String)
    }

    public struct Drink: Codable, Equatable, Sendable {
        public var name: String?
        public var mg: Double?
        public var provenance: CaffeineAtTime.Provenance?
        public var timeSpec: CaffeineQuestion.TimeSpec
        public var dayOffset: Int
        public var at: Millis?
        public var asked: CaffeineAtTime.AskedDrink?
    }

    public var drink: Drink?
    public var targetSpecs: [CaffeineQuestion.TimeSpec]
    public var targets: [Millis?]
    public var sleepAt: Millis?
    public var sleepChip: CaffeineAtTime.SleepTimeChip?
    public var duplicate: CaffeineAtTime.DuplicateQuestion?
    /// Up to 3 records offered after an unclear correction.
    public var candidateIDs: [String]
    /// The two instants of a repeated wall time, per slot.
    public var repeated: [Slot: [Millis]]
    /// A skipped local time, per slot: the person asks with another.
    public var skipped: Set<Slot>
    /// "Amount kept: 126 mg (you entered it)" and similar code-written lines.
    public var note: String?
    public var result: CaffeineAtTime.Result?
    public var halfLifeHours: Double
    public var capturedAt: Millis
    public var timeZoneID: String

    public static let maxCandidates = 3
    public static let enterAmountLabel = "Enter Amount"
    public static let sleepPickerLabel = "Sleep Time"
    public static let pickTimeLine = "Pick the time."
    public static let skippedTimeLine = "Clocks skip that time. Ask with another time."
    public static let skippedSleepLine = "Clocks skip that time tonight. Pick another sleep time."
    public static let repeatedTimeLine = "That time happens twice tonight. Pick one."
    public static let duplicateLine = "A logged drink with the same amount is within 30 minutes."
    public static let amountLine = "Enter the caffeine amount from the label or menu."
    public static func amountKeptLine(_ mg: Double) -> String { "Amount kept: \(numberText(mg)) mg (you entered it)" }
    public static let defaultTargetCount = 3

    // MARK: Start

    public static func start(_ parsed: CaffeineQuestion.Parsed, question: String, db: CaffeineDatabase?, doses: [Dose], sleeps: [SleepSession],
                             halfLifeHours: Double, now: Millis, clock: LocalClock) -> CaffeineAtTimeCard {
        var drink: Drink?
        if parsed.drinkMentioned || parsed.drinkMg != nil {
            var d = Drink(name: nil, mg: parsed.drinkMg, provenance: parsed.drinkMg == nil ? nil : .typed,
                          timeSpec: parsed.drinkTime ?? .now, dayOffset: parsed.drinkDayOffset, at: nil, asked: nil)
            if let named = namedDrink(in: question, db: db, now: now, clock: clock) {
                d.name = named.name
                if d.mg == nil, let mg = named.mg { d.mg = mg; d.provenance = named.provenance }
            }
            drink = d
        }
        var card = CaffeineAtTimeCard(
            drink: drink, targetSpecs: parsed.targets, targets: [], sleepAt: nil,
            sleepChip: parsed.targets.contains(.sleepTime) ? CaffeineAtTime.recentSleepStart(sleeps, now: now, clock: clock) : nil,
            duplicate: nil, candidateIDs: [], repeated: [:], skipped: [], note: nil, result: nil,
            halfLifeHours: halfLifeHours, capturedAt: now, timeZoneID: clock.calendar.timeZone.identifier)
        card.resolve(doses: doses, now: now)
        return card
    }

    /// The drink named in a longer sentence, with its amount when the
    /// database gives one (a stated size, else the record's serving).
    static func namedDrink(in text: String, db: CaffeineDatabase?, now: Millis, clock: LocalClock) -> (name: String, mg: Double?, provenance: CaffeineAtTime.Provenance?)? {
        let folded = " " + text.lowercased().replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." }).joined(separator: " ") + " "
        guard let phrase = TypedDrinkEntry.knownPhrases.first(where: { folded.contains(" " + $0 + " ") }) else { return nil }
        let volume = Volume.parse(text).first
        let lookup = (volume.map { $0.label + " " } ?? "") + phrase
        guard case .entry(let entry) = TypedDrinkEntry.parse(lookup, db: db, now: now, clock: clock) else { return nil }
        let mg = Double(entry.draft.mg)
        return (entry.draft.source, mg, mg == nil ? nil : provenance(entry.amountSource, db: db))
    }

    static func provenance(_ source: TypedDrinkEntry.AmountSource, db: CaffeineDatabase?) -> CaffeineAtTime.Provenance? {
        switch source {
        case .typedMg: return .typed
        case .chipSize(let id): return .database(entryID: "preset:\(id)", serving: TypedDrinkEntry.presetServings[id]?.serving ?? "")
        case .quickAddDefault(let id, let serving): return .database(entryID: "preset:\(id)", serving: serving)
        case .database(let id, let serving): return .database(entryID: id, serving: serving)
        case .scaled(let id, let volume): return .database(entryID: id, serving: "scaled to \(volume)")
        case .none: return nil
        }
    }

    // MARK: Resolve

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    /// Turns specs into instants where they're clear, asks the duplicate
    /// question when it applies, and computes rows once nothing is pending.
    public mutating func resolve(doses: [Dose], now: Millis) {
        result = nil
        if var d = drink {
            if d.at == nil { d.at = instant(.drink, d.timeSpec, anchor: now, dayOffset: d.dayOffset, now: now) }
            drink = d
        }
        let anchor = max(now, drink?.at ?? now)
        if targetSpecs.isEmpty {
            let hour = Millis(hourMs)
            let first = (anchor / hour).rounded(.down) * hour + hour
            targets = (0..<Self.defaultTargetCount).map { Optional(first + Millis($0) * hour) }
        } else if targets.count != targetSpecs.count {
            targets = targetSpecs.enumerated().map { i, spec in spec == .sleepTime ? nil : instant(.target(i), spec, anchor: anchor, dayOffset: 0, now: now) }
        }
        if let d = drink, d.asked == nil, duplicate == nil, let mg = d.mg, let at = d.at {
            let unlogged = CaffeineAtTime.UnloggedDrink(mg: mg, at: at, provenance: d.provenance ?? .typed)
            switch CaffeineAtTime.checkAskedDrink(unlogged, doses: doses, now: now) {
            case .resolved(let asked): drink?.asked = asked
            case .needsChoice(let question): duplicate = question
            }
        }
        guard isComplete else { return }
        var instants: [Millis] = targets.compactMap { $0 }
        if let sleepAt { instants.insert(sleepAt, at: 0) }
        result = CaffeineAtTime.evaluate(doses: doses, asked: drink?.asked, halfLifeHours: halfLifeHours, targets: instants, now: now)
    }

    private mutating func instant(_ slot: Slot, _ spec: CaffeineQuestion.TimeSpec, anchor: Millis, dayOffset: Int, now: Millis) -> Millis? {
        let local: CutoffScenario.LocalTime
        switch spec {
        case .now: return now
        case .sleepTime, .ambiguousHour, .into: return nil
        case .clock(let h, let m):
            local = slot == .drink
                ? CaffeineQuestion.drinkLocalTime(hour: h, minute: m, dayOffset: dayOffset, now: now, timeZone: timeZone)
                : CaffeineQuestion.targetLocalTime(hour: h, minute: m, after: anchor, timeZone: timeZone)
        }
        switch CutoffScenario.resolve(local, in: timeZone) {
        case .exact(let t): return t
        case .repeated(let first, let second): repeated[slot] = [first, second]; return nil
        case .skipped, .invalid: skipped.insert(slot); return nil
        }
    }

    public var needsAmount: Bool { drink != nil && drink?.mg == nil }
    public var needsSleepTime: Bool { targetSpecs.contains(.sleepTime) && sleepAt == nil }
    public var isComplete: Bool {
        guard skipped.isEmpty, duplicate == nil, !needsAmount, !needsSleepTime else { return false }
        if let d = drink, d.at == nil || d.asked == nil { return false }
        if targetSpecs.isEmpty { return !targets.isEmpty && !targets.contains(nil) }
        guard targets.count == targetSpecs.count else { return false }
        return !zip(targetSpecs, targets).contains { spec, t in spec != .sleepTime && t == nil }
    }

    /// The chips the card shows now, in order.
    public var choices: [Choice] {
        var out: [Choice] = []
        if let d = drink, d.at == nil {
            if let pair = repeated[.drink] { out += [.instant(.drink, pair[0], first: true), .instant(.drink, pair[1], first: false)] }
            else { out += CaffeineQuestion.choices(for: d.timeSpec).map { .time(.drink, $0) } }
        }
        for (i, spec) in targetSpecs.enumerated() where spec != .sleepTime && (targets.indices.contains(i) ? targets[i] : nil) == nil {
            if let pair = repeated[.target(i)] { out += [.instant(.target(i), pair[0], first: true), .instant(.target(i), pair[1], first: false)] }
            else { out += CaffeineQuestion.choices(for: spec).map { .time(.target(i), $0) } }
        }
        if duplicate != nil { out += CaffeineAtTime.DuplicateChoice.allCases.map { .duplicate($0) } }
        if let pair = repeated[.sleep] { out += [.instant(.sleep, pair[0], first: true), .instant(.sleep, pair[1], first: false)] }
        else if needsSleepTime, sleepChip != nil { out.append(.sleepChip) }
        if needsAmount { out += candidateIDs.map { .candidate(entryID: $0) } }
        return out
    }

    // MARK: Answers

    public mutating func choose(_ choice: Choice, db: CaffeineDatabase?, doses: [Dose], now: Millis) {
        switch choice {
        case .time(let slot, let spec):
            if slot == .drink, var d = drink { d.timeSpec = spec; d.at = nil; d.asked = nil; drink = d; duplicate = nil; targets = [] }
            if case .target(let i) = slot, targetSpecs.indices.contains(i) { targetSpecs[i] = spec; targets = [] }
        case .instant(let slot, let t, _):
            repeated[slot] = nil
            if slot == .sleep { sleepAt = t }
            if slot == .drink { drink?.at = t; drink?.asked = nil; duplicate = nil; targets = [] }
            if case .target(let i) = slot, targets.indices.contains(i) { targets[i] = t }
        case .duplicate(let answer):
            guard let question = duplicate else { return }
            drink?.asked = question.answer(answer)
            duplicate = nil
        case .sleepChip:
            guard let chip = sleepChip else { return }
            setSleep(chip, now: now)
        case .candidate(let id):
            guard let entry = db?.entry(id: id) else { return }
            let amount = TypedDrinkEntry.recordAmount(entry, volume: nil, db: db)
            drink?.name = entry.displayName
            drink?.mg = amount.mg.map(Double.init)
            drink?.provenance = amount.mg == nil ? nil : Self.provenance(amount.source, db: db)
            drink?.asked = nil
            if amount.mg != nil { candidateIDs = [] }
            note = amount.mg == nil ? Self.amountLine : nil
        }
        resolve(doses: doses, now: now)
    }

    /// The picker's wall time: its next occurrence after the drink or now.
    public mutating func setSleepTime(hour: Int, minute: Int, doses: [Dose], now: Millis) {
        setSleep(CaffeineAtTime.SleepTimeChip(minuteOfDay: hour * 60 + minute, nights: 0), now: now)
        resolve(doses: doses, now: now)
    }

    /// Through the shared resolver: a skipped time asks for another, a
    /// repeated one offers both instants; nothing is shifted or picked.
    private mutating func setSleep(_ chip: CaffeineAtTime.SleepTimeChip, now: Millis) {
        sleepAt = nil
        repeated[.sleep] = nil
        skipped.remove(.sleep)
        switch chip.nextStart(after: max(now, drink?.at ?? now), timeZone: timeZone) {
        case .exact(let t): sleepAt = t
        case .repeated(let first, let second): repeated[.sleep] = [first, second]
        case .skipped, .invalid: skipped.insert(.sleep)
        }
    }

    /// "Enter Amount": the person's own mg, 1–1999 whole mg.
    @discardableResult
    public mutating func setAmount(_ text: String, doses: [Dose], now: Millis) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"\s*mg$"#, with: "", options: [.regularExpression, .caseInsensitive])
        guard drink != nil, trimmed.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
              let mg = Double(trimmed), CaffeineLog.isValidAmount(mg) else { return false }
        drink?.mg = mg; drink?.provenance = .typed; drink?.asked = nil
        candidateIDs = []; note = nil
        resolve(doses: doses, now: now)
        return true
    }

    // MARK: Correction

    /// "Actually a caramel latte", "it's tea", "make it a Celsius".
    public static func correctionPhrase(_ input: String) -> String? {
        let text = input.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard let r = text.range(of: #"^(?:no,?\s+)?(?:actually,?|correction:?|make it|it's|it is|it was|i meant)\s+(?:(?:a|an)\s+)?"#, options: .regularExpression) else { return nil }
        let phrase = String(text[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        return phrase.isEmpty ? nil : phrase
    }

    /// Re-resolves the drink. A typed amount is kept and only the name
    /// changes; a database amount takes the new record's serving (maker
    /// and Branded records never scale). Unclear text offers up to three
    /// records plus Enter Amount; a Not in Database brand or matcha asks
    /// for the amount. Returns false when there's no drink to correct.
    @discardableResult
    public mutating func correct(_ phrase: String, db: CaffeineDatabase?, doses: [Dose], now: Millis, clock: LocalClock) -> Bool {
        guard drink != nil else { return false }
        let parsed = TypedDrinkEntry.parse(phrase, db: db, now: now, clock: clock)
        var name: String?
        var mg: Double?
        var source: CaffeineAtTime.Provenance?
        if case .entry(let entry) = parsed {
            name = entry.draft.source.isEmpty ? nil : entry.draft.source
            mg = Double(entry.draft.mg)
            source = mg == nil ? nil : Self.provenance(entry.amountSource, db: db)
        }
        let unrecorded = DrinkPhotoMatcher.unrecordedBrand(in: phrase)
        if name == nil { name = unrecorded ?? DrinkPhotoConfirmation.titleCase(phrase) }
        drink?.name = name
        drink?.asked = nil
        duplicate = nil
        candidateIDs = []
        if drink?.provenance == .typed, let kept = drink?.mg {
            note = Self.amountKeptLine(kept)
        } else if let mg {
            drink?.mg = mg; drink?.provenance = source; note = nil
        } else {
            drink?.mg = nil; drink?.provenance = nil
            if unrecorded == nil, let db { candidateIDs = DrinkPhotoMatcher.search(phrase, in: db).prefix(Self.maxCandidates).map(\.entry.id) }
            note = unrecorded == nil ? Self.amountLine : DrinkPhotoMatcher.unrecordedBrandMessage
        }
        resolve(doses: doses, now: now)
        return true
    }

    // MARK: Log This Drink

    /// The confirm card's draft for a Not Logged drink. Saving stays the
    /// confirm card's Save; this writes nothing.
    public var logDraft: CustomDoseDraft? {
        guard case .notLogged(let unlogged)? = drink?.asked else { return nil }
        return CustomDoseDraft(mg: numberText(unlogged.mg), source: drink?.name ?? "", timestamp: unlogged.at, note: "")
    }

    // MARK: Display

    public struct RowView: Equatable, Sendable {
        public var label: String
        public var value: String
        public var spoken: String
    }

    public func rows(text: DateText) -> [RowView] {
        guard let result else { return [] }
        return result.rows.enumerated().map { i, row in
            let time = text.clockTime(row.at)
            let label = (i == 0 && sleepAt != nil) ? "At Sleep Time · \(time)" : "At \(time)"
            return RowView(label: label, value: row.valueText, spoken: "\(label), \(row.valueText)")
        }
    }

    /// Code-written lines under the rows: the drink, its source, the record count.
    public func lines(text: DateText, db: CaffeineDatabase?) -> [String] {
        var out: [String] = []
        if let d = drink {
            var parts: [String] = []
            if let name = d.name, !name.isEmpty { parts.append(name) }
            if let mg = d.mg { parts.append("\(numberText(mg)) mg") }
            if let at = d.at { parts.append(text.clockTime(at)) }
            if let asked = d.asked { parts.append(asked.label) }
            if !parts.isEmpty { out.append(parts.joined(separator: " · ")) }
            switch d.provenance {
            case .typed?: out.append("Amount: You Entered It")
            case .database(let id, let serving)?: out.append("Amount: " + Self.sourceText(entryID: id, serving: serving, db: db))
            case nil: break
            }
        }
        if let note { out.append(note) }
        if duplicate != nil { out.append(Self.duplicateLine) }
        if skipped.contains(.sleep) { out.append(Self.skippedSleepLine) }
        if !skipped.subtracting([.sleep]).isEmpty { out.append(Self.skippedTimeLine) }
        else if !choices.isEmpty, duplicate == nil, !needsAmount { out.append(repeated.isEmpty ? Self.pickTimeLine : Self.repeatedTimeLine) }
        if let result {
            out.append("Includes \(result.recordedCount) recorded \(result.recordedCount == 1 ? "drink" : "drinks")")
            if result.includesSample { out.append("Includes Sample Data") }
        }
        return out
    }

    static func sourceText(entryID: String, serving: String, db: CaffeineDatabase?) -> String {
        if entryID.hasPrefix("preset:") { return "Quick Add · \(serving)" }
        if let entry = db?.entry(id: entryID) {
            if let fdc = entry.fdcId { return "USDA · FDC \(fdc) · \(serving)" }
            return "\(entry.brand ?? entry.displayName) · \(serving)"
        }
        return serving
    }

    public func label(for choice: Choice, text: DateText, db: CaffeineDatabase?, now: Millis) -> String {
        let clock = LocalClock(timeZone: timeZone)
        switch choice {
        case .time(_, let spec):
            switch spec {
            case .now: return "Now"
            case .clock(let h, let m), .ambiguousHour(let h, let m), .into(let h, let m):
                return text.clockTime(clock.setTime(now, hour: h, minute: m))
            case .sleepTime: return Self.sleepPickerLabel
            }
        case .instant(_, let t, let first): return "\(text.clockTime(t)) · \(first ? "First" : "Second")"
        case .duplicate(let answer): return answer.label
        case .sleepChip:
            guard let chip = sleepChip else { return Self.sleepPickerLabel }
            return chip.label(clockTime: text.clockTime(clock.setTime(now, hour: chip.minuteOfDay / 60, minute: chip.minuteOfDay % 60)))
        case .candidate(let id): return db?.entry(id: id).map { DrinkPhotoConfirmation.titleCase($0.displayName) } ?? id
        }
    }
}
