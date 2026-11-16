import Foundation

/// Typed drink entries with Apple Intelligence off (CPO, Nov 16). A small,
/// deterministic reader for one drink: "12oz coffee", "espresso 64mg",
/// "tea at 9am", "celsius". It only fills the entry card and never saves;
/// whether a card may save at once is `SavePolicy`'s decision. Every amount
/// is the person's own typed mg, a Quick Add chip value, or a bundled
/// database record (scaled only for generic USDA records), and the card
/// says which. Anything it can't read gets a plain message and the manual
/// card instead of a refusal. Questions, advice, negation and corrections
/// are never entries.
public enum TypedDrinkEntry {
    /// Where the amount on the card came from.
    public enum AmountSource: Equatable, Sendable {
        /// The person's own mg.
        case typedMg
        /// A drink plus the size of its Quick Add chip: the chip's value, no lookup.
        case chipSize(presetID: String)
        /// A bare drink name: its Quick Add chip value at the chip's serving.
        case quickAddDefault(presetID: String, serving: String)
        /// A database record at one of its listed servings.
        case database(entryID: String, serving: String)
        /// A generic USDA record converted to the typed size.
        case scaled(entryID: String, volume: String)
        /// No sourced amount: the person enters it.
        case none
    }

    public struct Entry: Equatable, Sendable {
        public var draft: CustomDoseDraft
        public var amountSource: AmountSource
        /// The card's one line on where the number came from.
        public var provenance: String
        /// Whether the person stated a time; otherwise the card shows now.
        public var timeStated: Bool
    }

    public enum Result: Equatable, Sendable {
        case entry(Entry)
        /// Plain message; the app opens the manual card with its drink chips.
        case unreadable(String)
    }

    /// The Quick Add chips' servings (docs/research/caffeine.md "Presets
    /// state their serving"). Only Drip is backed by a generic USDA record
    /// (SR Legacy 171890, 1 cup (8 fl oz) = 95 mg), so only Drip scales.
    public struct PresetServing: Equatable, Sendable {
        public let serving: String
        public let milliliters: Double?
        public let usdaEntryID: String?
    }
    public static let presetServings: [String: PresetServing] = [
        "espresso": PresetServing(serving: "1 shot", milliliters: nil, usdaEntryID: nil),
        "drip": PresetServing(serving: "8 fl oz", milliliters: 8 * Volume.mlPerFlOz, usdaEntryID: "fdc:171890"),
        "energy": PresetServing(serving: "16 fl oz", milliliters: 16 * Volume.mlPerFlOz, usdaEntryID: nil),
    ]

    public static let oneDrinkMessage = "One drink at a time. Enter the first one here, then the next."
    public static let unreadableMessage = "I couldn’t read that drink. Pick a drink below or enter it yourself."
    public static let amountRangeMessage = "Amounts are whole numbers from 1 to 1999 mg. Enter the amount here."
    public static let futureTimeMessage = "That time hasn’t happened yet today. Pick the time here."
    public static let ambiguousTimeMessage = "That local time is skipped or happens twice today. Pick the exact time here."
    public static let enterAmountLine = "Enter the caffeine amount from the label or menu."

    // MARK: Vocabulary

    static let presetPhrases: [String: String] = [
        "espresso": "espresso", "espresso shot": "espresso", "shot espresso": "espresso",
        "coffee": "drip", "drip": "drip", "drip coffee": "drip", "brewed coffee": "drip", "black coffee": "drip", "hot coffee": "drip",
        "energy drink": "energy",
    ]
    /// Generic drinks and their USDA record, shown under the name given.
    static let genericPhrases: [String: (id: String, name: String)] = [
        "tea": ("fdc:173227", "Tea"), "black tea": ("fdc:173227", "Black Tea"), "hot tea": ("fdc:173227", "Tea"),
        "latte": ("fdc:2710386", "Latte"), "iced latte": ("fdc:2710431", "Iced Latte"),
        "cappuccino": ("fdc:2710472", "Cappuccino"), "mocha": ("fdc:2710410", "Cafe Mocha"), "cafe mocha": ("fdc:2710410", "Cafe Mocha"),
        "decaf": ("fdc:171889", "Decaf Coffee"), "decaf coffee": ("fdc:171889", "Decaf Coffee"),
    ]
    /// Known drinks with no single sourced amount: the person enters it.
    static let unsourcedPhrases: [String: String] = ["cold brew": "Cold Brew", "iced coffee": "Iced Coffee", "green tea": "Green Tea"]
    static let drinkWords = #"\b(coffees?|espressos?|teas?|lattes?|cappuccinos?|mochas?|matcha|drip|cold brew|energy drinks?|caffeine|sodas?|colas?|decaf|brew|drinks?|shots?)\b"#
    static let multiWords: Set<String> = ["and", "then", "plus", "both", "another", "two", "three", "four", "five", "with", "also"]
    static let sizeMismatchWords: Set<String> = ["double", "triple", "quad", "doppio", "large", "small", "medium", "venti", "grande", "tall"]
    static let fillerWords: Set<String> = ["a", "an", "one", "some", "my", "cup", "mug", "can", "bottle", "glass", "of", "single", "shot", "just", "x"]

    // MARK: Parse

    /// `nil` when the text isn't a typed drink entry, so other routes decide.
    public static func parse(_ input: String, db: CaffeineDatabase?, now: Millis, clock: LocalClock) -> Result? {
        var text = input.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, ".!".contains(last) { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text != "log caffeine", !text.contains("?") else { return nil }
        if matches(#"^(how|what|when|why|where|which|who|should|can|could|would|will|is|are|am|do|does|did|if|actually|correction|make it|it was|was|were|help|show|open)\b"#, text) { return nil }
        if matches(#"\b(should|would|could|recommend|don't|didn't|dont|didnt|do not|did not|not|never|no|cancel|delete|undo|remove|sleep|slept|if)\b"#, text) { return nil }

        // Time.
        var rest = text
        var timeParts: [String]?
        var nowStated = false
        let timePattern = #"\b(?:(yesterday|today)\s+)?(?:at\s+)?(1[0-2]|[1-9])(?::([0-5][0-9]))?\s*(am|pm)\b"#
        let times = all(timePattern, rest)
        if times.count > 1 { return .unreadable(unreadableMessage) }
        if let time = times.first { timeParts = time.groups; rest = remove(time.range, from: rest) }
        if matches(#"\b(?:right\s+)?now\b"#, rest) {
            if timeParts != nil { return .unreadable(unreadableMessage) }
            nowStated = true
            rest = rest.replacingOccurrences(of: #"\b(?:right\s+)?now\b"#, with: " ", options: .regularExpression)
        }

        // The person's own mg.
        // Signed, grouped or malformed amounts ask again (`MgToken`).
        let amounts = MgToken.matches(in: rest)
        if amounts.count > 1 { return .unreadable(unreadableMessage) }
        var typedMg: Double?
        if let amount = amounts.first {
            guard let value = amount.value else { return .unreadable(amountRangeMessage) }
            typedMg = value
            rest = remove(amount.range, from: rest)
        }

        // A barcode typed in.
        var barcodeEntry: CaffeineDatabase.Entry?
        if let code = all(#"\b\d{8,14}\b"#, rest).first {
            barcodeEntry = db?.entry(gtin: code.groups.isEmpty ? String(rest[code.range]) : code.groups[0])
            rest = remove(code.range, from: rest)
        }

        // A size.
        let volumePattern = #"(?i)(\d{1,4}(?:[.,]\d{1,2})?)\s*(fl\.?\s*oz\.?|fluid\s+ounces?|floz|oz\.?|ml|millilit(?:er|re)s?|l|lit(?:er|re)s?)(?![a-z])"#
        let sizes = all(volumePattern, rest)
        var volume: Volume?
        if !sizes.isEmpty {
            let found = Volume.parse(sizes.map { String(rest[$0.range]) }.joined(separator: " "))
            guard found.count == 1, sizes.count == 1 else { return .unreadable(unreadableMessage) }
            volume = found[0]
            rest = remove(sizes[0].range, from: rest)
        }

        // What's left names the drink.
        rest = rest.replacingOccurrences(of: #"^\s*(?:i\s+)?(?:just\s+)?(?:had|drank|log|logged|got)\b"#, with: " ", options: .regularExpression)
        let led = rest != text && matches(#"^\s*(?:i\s+)?(?:just\s+)?(?:had|drank|log|logged|got)\b"#, text)
        var words = rest.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "-" }).map(String.init)
        let hasDrinkWord = matches(drinkWords, words.joined(separator: " "))
        if hasDrinkWord, words.contains(where: { multiWords.contains($0) || isPluralDrink($0) }) { return .unreadable(oneDrinkMessage) }
        if words.contains(where: { $0.allSatisfy(\.isNumber) }) {
            return hasDrinkWord || typedMg != nil || led ? .unreadable(unreadableMessage) : nil
        }
        let mismatch = words.contains { sizeMismatchWords.contains($0) }
        words.removeAll { fillerWords.contains($0) || sizeMismatchWords.contains($0) }
        let phrase = words.joined(separator: " ")
        let drinkish = hasDrinkWord || typedMg != nil || barcodeEntry != nil || led

        if let typedMg, !(typedMg.isFinite && typedMg.rounded() == typedMg && typedMg >= 1 && typedMg <= 1999) {
            return .unreadable(amountRangeMessage)
        }

        // Resolve the drink.
        enum Drink { case preset(String), record(CaffeineDatabase.Entry, String), unsourced(String), brandOnly(String), typedOnly(String) }
        var drink: Drink?
        if let barcodeEntry {
            guard phrase.isEmpty else { return .unreadable(unreadableMessage) }
            drink = .record(barcodeEntry, barcodeEntry.displayName)
        } else if phrase.isEmpty {
            return drinkish ? .unreadable(unreadableMessage) : nil
        } else if let brand = DrinkPhotoMatcher.unrecordedBrand(in: phrase) {
            drink = .brandOnly(brand)
        } else if let preset = presetPhrases[phrase] {
            drink = .preset(preset)
        } else if let generic = genericPhrases[phrase], let entry = db?.entry(id: generic.id) {
            drink = .record(entry, generic.name)
        } else if let name = unsourcedPhrases[phrase] {
            drink = .unsourced(name)
        } else if let db, case .one(let entry) = confidentBrand(phrase, in: db) {
            drink = .record(entry, entry.displayName)
        } else if let db, case .several = confidentBrand(phrase, in: db), words.allSatisfy({ $0.allSatisfy(\.isLetter) }) {
            // Named in several records: the name, and the person enters the amount.
            drink = .typedOnly(words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " "))
        } else if typedMg != nil, words.count <= 3, words.allSatisfy({ $0.allSatisfy(\.isLetter) }) {
            drink = .typedOnly(words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " "))
        }
        guard let drink else { return drinkish ? .unreadable(unreadableMessage) : nil }

        // Time, last: a readable drink at an impossible time asks for the time.
        var timestamp = now
        if let timeParts, let hour12 = Int(timeParts[1]) {
            let minute = Int(timeParts[2]) ?? 0
            let hour = hour12 % 12 + (timeParts[3] == "pm" ? 12 : 0)
            let base = timeParts[0] == "yesterday" ? clock.addingDays(-1, to: now) : now
            let day = clock.calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: base / 1000))
            guard let y = day.year, let m = day.month, let d = day.day else { return .unreadable(unreadableMessage) }
            guard case .exact(let ms) = CutoffScenario.resolve(.init(year: y, month: m, day: d, hour: hour, minute: minute), in: clock.timeZone) else {
                return .unreadable(ambiguousTimeMessage)
            }
            guard ms <= now else { return .unreadable(futureTimeMessage) }
            timestamp = ms
        }
        let timeStated = timeParts != nil || nowStated

        func make(_ source: String, _ mg: Int?, _ amount: AmountSource, _ provenance: String) -> Result {
            if let typedMg {
                return .entry(Entry(draft: CustomDoseDraft(mg: numberText(typedMg), source: source, timestamp: timestamp, note: ""),
                                    amountSource: .typedMg, provenance: "Typed amount · mg", timeStated: timeStated))
            }
            return .entry(Entry(draft: CustomDoseDraft(mg: mg.map(String.init) ?? "", source: source, timestamp: timestamp, note: ""),
                                amountSource: mg == nil ? .none : amount, provenance: mg == nil ? provenance : provenanceFor(amount, db: db), timeStated: timeStated))
        }

        switch drink {
        case .brandOnly(let brand):
            return make(brand, nil, .none, DrinkPhotoMatcher.unrecordedBrandMessage)
        case .unsourced(let name), .typedOnly(let name):
            return make(name, nil, .none, enterAmountLine)
        case .preset(let id):
            guard let preset = CaffeinePreset.all.first(where: { $0.id == id }), let serving = presetServings[id] else {
                return .unreadable(unreadableMessage)
            }
            if mismatch { return make(preset.label, nil, .none, enterAmountLine) }
            guard let volume else {
                return make(preset.label, Int(preset.mg), .quickAddDefault(presetID: id, serving: serving.serving), "")
            }
            if let ml = serving.milliliters, abs(volume.milliliters - ml) / ml < 0.03 {
                return make(preset.label, Int(preset.mg), .chipSize(presetID: id), "")
            }
            if let recordID = serving.usdaEntryID, let db, let record = db.entry(id: recordID), let mg = db.mg(for: record, volume: volume) {
                return make("Coffee", mg, .scaled(entryID: recordID, volume: volume.label), "")
            }
            return make(preset.label, nil, .none, enterAmountLine)
        case .record(let entry, let name):
            if mismatch { return make(name, nil, .none, enterAmountLine) }
            let amount = recordAmount(entry, volume: volume, db: db)
            return make(name, amount.mg, amount.source, enterAmountLine)
        }
    }

    /// A record's amount: at a stated size, scaled for generic USDA records
    /// or a published serving within 3% for maker and Branded records; with
    /// no size, its only serving or its "1 cup (8 fl oz)". Else no amount.
    public static func recordAmount(_ entry: CaffeineDatabase.Entry, volume: Volume?, db: CaffeineDatabase?) -> (mg: Int?, source: AmountSource) {
        if let volume {
            if !entry.publishedServingsOnly, let db, let mg = db.mg(for: entry, volume: volume) {
                return (mg, .scaled(entryID: entry.id, volume: volume.label))
            }
            if let serving = entry.servings.first(where: { s in
                Volume.parse(s.label).first.map { abs($0.milliliters - volume.milliliters) / volume.milliliters < 0.03 } ?? false
            }) {
                return (serving.mg, .database(entryID: entry.id, serving: serving.label))
            }
            return (nil, .none)
        }
        let serving = entry.servings.count == 1 ? entry.servings[0] : entry.servings.first { $0.label == "1 cup (8 fl oz)" }
        guard let serving else { return (nil, .none) }
        return (serving.mg, .database(entryID: entry.id, serving: serving.label))
    }

    /// Drink phrases the reader knows by name, longest first, for finding
    /// the drink inside a longer sentence (follow-up questions).
    public static var knownPhrases: [String] {
        (Array(presetPhrases.keys) + Array(genericPhrases.keys) + Array(unsourcedPhrases.keys)
            + DrinkPhotoMatcher.unrecordedBrands.flatMap(\.phrases)).sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
    }

    public static let manualSourceLine = "Manual · local time"

    /// The entry card's source line: where the number came from, while the
    /// drink and amount are still the ones read from the text; "Manual"
    /// once the person changes either, or when nothing was sourced.
    public static func sourceLine(for draft: CustomDoseDraft, entry: Entry?) -> String {
        guard let entry, entry.amountSource != .none, draft.mg == entry.draft.mg, draft.source == entry.draft.source else {
            return manualSourceLine
        }
        return entry.provenance + " · local time"
    }

    /// The card's provenance line for a sourced amount.
    public static func provenanceFor(_ amount: AmountSource, db: CaffeineDatabase?) -> String {
        func origin(_ id: String) -> String {
            guard let db, let entry = db.entry(id: id) else { return id }
            return (db.source(for: entry)?.shortName ?? entry.source) + " · " + entry.reference
        }
        switch amount {
        case .typedMg: return "Typed amount · mg"
        case .chipSize(let id):
            let label = CaffeinePreset.all.first { $0.id == id }?.label ?? id
            return "Quick Add · \(label) · \(presetServings[id]?.serving ?? "")"
        case .quickAddDefault(_, let serving): return "Quick Add Default · \(serving)"
        case .database(let id, let serving): return origin(id) + " · " + serving
        case .scaled(let id, let volume): return origin(id) + " · scaled to " + volume
        case .none: return enterAmountLine
        }
    }

    /// A named product the database is sure of. Unlike the photo search,
    /// every typed word must appear in the record's name or brand (so
    /// "coffee blah" matches nothing), and the record those words cover
    /// most, by the photo search's word weights, must stand clear of the next.
    enum BrandMatch { case one(CaffeineDatabase.Entry), several, none }
    static func confidentBrand(_ phrase: String, in db: CaffeineDatabase) -> BrandMatch {
        let query = DrinkPhotoMatcher.tokens(phrase)
        guard !query.isEmpty else { return .none }
        let idf = DrinkPhotoMatcher.inverseFrequency(db)
        let ranked = db.entries.compactMap { entry -> (entry: CaffeineDatabase.Entry, score: Double)? in
            let words = DrinkPhotoMatcher.entryTokens(entry)
            guard query.isSubset(of: words) else { return nil }
            let total = words.reduce(0) { $0 + (idf[$1] ?? 1) }
            return (entry, query.reduce(0) { $0 + (idf[$1] ?? 1) } / max(total, .leastNonzeroMagnitude))
        }.sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.id < $1.entry.id }
        guard let first = ranked.first else { return .none }
        guard first.score >= 0.5, first.score - (ranked.dropFirst().first?.score ?? 0) >= DrinkPhotoMatcher.confidentMargin else { return .several }
        return .one(first.entry)
    }

    static func isPluralDrink(_ word: String) -> Bool {
        ["coffees", "espressos", "teas", "lattes", "cappuccinos", "mochas", "drinks", "shots", "sodas", "colas", "cans"].contains(word)
    }

    // MARK: Regex helpers

    struct Match { let range: Range<String.Index>; let groups: [String] }
    static func matches(_ pattern: String, _ text: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
    static func all(_ pattern: String, _ text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            guard let range = Range(m.range, in: text) else { return nil }
            let groups = (1..<max(m.numberOfRanges, 1)).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
            return Match(range: range, groups: groups)
        }
    }
    static func remove(_ range: Range<String.Index>, from text: String) -> String {
        var copy = text; copy.replaceSubrange(range, with: " "); return copy
    }
}
