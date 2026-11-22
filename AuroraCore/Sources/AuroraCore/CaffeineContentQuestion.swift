import Foundation

/// "How much caffeine does beer have?", "Is there caffeine in a latte?":
/// a question about a drink, not about the person's own caffeine. Answered
/// in code from the bundled `CaffeineDatabase` only, AI on or off. A drink
/// the database doesn't list gets a plain "no entry" line, never a guessed
/// amount, and never the generic "What would you like to do?" menu.
///
/// Questions about the person's own caffeine at a time ("how much caffeine
/// will I have at 10pm") stay with `CaffeineQuestion.route`, which the app
/// checks first; anything naming the person, a time or an amount returns nil
/// here.
public enum CaffeineContentQuestion {
    public enum Answer: Equatable, Sendable {
        /// The drink's caffeine at one of its record's servings.
        case found(drink: String, mg: Int, serving: String, source: String)
        /// A drink that has no caffeine (beer, water, milk). Not a database
        /// record: the database holds caffeinated drinks only.
        case noCaffeine(drink: String)
        /// More than one record fits the words given.
        case several(drink: String)
        /// No record in the database for this drink.
        case notInDatabase(drink: String)

        public var message: String {
            switch self {
            case .found(let drink, let mg, let serving, let source):
                return "\(CaffeineContentQuestion.capitalized(drink)): \(mg) mg of caffeine per \(serving). Source: \(source)."
            case .noCaffeine(let drink):
                return "\(CaffeineContentQuestion.capitalized(drink)): about 0 mg of caffeine. It isn’t a caffeinated drink, so Aurora’s caffeine database doesn’t list it."
            case .several(let drink):
                return "Several drinks in Aurora’s caffeine database match “\(drink)”. Name the exact product and size."
            case .notInDatabase(let drink):
                return "Aurora’s caffeine database has no entry for \(drink), so there’s no caffeine amount to show."
            }
        }
    }

    /// A question shape; capture group 1 is the drink. A terse shape
    /// ("beer caffeine", "caffeine for a latte") answers only when it names a
    /// drink Aurora can place, so "how much caffeine is too much" still goes
    /// to the assistant instead of getting a "no entry" line.
    /// NSRegularExpression is immutable and safe to share across threads.
    struct Shape: @unchecked Sendable {
        let regex: NSRegularExpression
        let terse: Bool
        init(_ pattern: String, terse: Bool = false) {
            regex = try! NSRegularExpression(pattern: pattern)
            self.terse = terse
        }
    }

    /// Compiled once: a lookup runs in code on every send, before any model.
    static let shapes: [Shape] = [
        Shape(#"^how much caffeine (?:is |are )?(?:there )?(?:in|does|do) (.+?)(?: have| has| contain| contains)?$"#),
        Shape(#"^how many mg (?:of caffeine )?(?:is |are )?(?:there )?(?:in|does|do) (.+?)(?: have| has| contain| contains)?$"#),
        Shape(#"^(?:does|do) (.+?) (?:have|has|contain|contains) (?:any )?caffeine$"#),
        Shape(#"^is there (?:any )?caffeine in (.+)$"#),
        Shape(#"^what(?:'s| is) the caffeine(?: content| amount)? (?:in|of) (.+)$"#),
        Shape(#"^caffeine (?:in|content of) (.+)$"#),
        Shape(#"^(?:is|are) (.+?) caffeinated$"#),
        Shape(#"^(?:is|are) (.+?) caffeine[- ]free$"#),
        Shape(#"^(.+?) caffeine(?: content| amount| level)?$"#, terse: true),
        Shape(#"^caffeine (?:for |of )?(.+)$"#, terse: true),
        Shape(#"^how much caffeine (.+)$"#, terse: true),
        Shape(#"^(?:how many )?mg (?:of caffeine )?(?:in )?(.+)$"#, terse: true),
    ]
    /// Words that make it a question about the person, a time or a dose.
    nonisolated(unsafe) static let personalWords = try! NSRegularExpression(
        pattern: #"\b(i|i'm|i've|me|my|you|your|left|today|tonight|now|body|system|blood|day|week|yesterday|tomorrow|bed ?time|should|safe|limit)\b"#)
    nonisolated(unsafe) static let leadingFiller = try! NSRegularExpression(
        pattern: #"^(?:(?:a|one) (?:cup|can|glass|bottle|shot) of|(?:cup|can|glass|bottle|shot) of|a|an|the|one|some)\s+"#)

    /// Everyday drinks with no caffeine, matched on the whole phrase only, so
    /// "coffee stout" or "chocolate milk" never land here. Root beer stays
    /// out: some root beers (Barq's) have caffeine.
    static let noCaffeineDrinks: Set<String> = [
        "beer", "lager", "ale", "ipa", "stout", "cider", "hard cider",
        "wine", "red wine", "white wine", "rosé", "rose", "champagne", "prosecco", "sake",
        "spirits", "liquor", "vodka", "gin", "rum", "whiskey", "whisky", "tequila", "bourbon", "brandy",
        "water", "sparkling water", "seltzer", "club soda", "tonic water", "coconut water",
        "milk", "whole milk", "skim milk", "oat milk", "almond milk", "soy milk",
        "juice", "orange juice", "apple juice", "grape juice", "cranberry juice", "lemonade",
        "sprite", "7up", "7 up", "ginger ale", "fanta", "caffeine-free coke", "caffeine free coke",
        "caffeine-free diet coke", "caffeine free diet coke", "caffeine-free pepsi", "caffeine free pepsi",
    ]

    /// The answer, or nil when the text isn't a question about a drink's caffeine.
    public static func answer(_ input: String, db: CaffeineDatabase?) -> Answer? {
        guard let db else { return nil }
        return answer(input, index: Index(db))
    }

    /// The same answer against the bundled database, whose index is built
    /// once; the app calls this on every send.
    public static func answer(_ input: String) -> Answer? {
        guard let index = bundledIndex else { return nil }
        return answer(input, index: index)
    }

    static let bundledIndex: Index? = CaffeineDatabase.bundled.map(Index.init)

    static func answer(_ input: String, index: Index) -> Answer? {
        guard let parsed = parse(input) else { return nil }
        let answer = lookup(parsed.drink, index: index)
        if parsed.terse, case .notInDatabase = answer { return nil }
        return answer
    }

    /// The drink a content question names, lowercased, without articles.
    public static func drink(in input: String) -> String? { parse(input)?.drink }

    static func parse(_ input: String) -> (drink: String, terse: Bool)? {
        var text = input.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, "?.!".contains(last) { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 120 else { return nil }
        for shape in shapes {
            guard let captured = capture(shape.regex, text) else { continue }
            var drink = captured.trimmingCharacters(in: .whitespaces)
            if let filler = firstRange(leadingFiller, drink) { drink.removeSubrange(filler) }
            drink = drink.trimmingCharacters(in: .whitespaces)
            guard !drink.isEmpty, drink.count <= 40,
                  !drink.contains(where: \.isNumber) || noCaffeineDrinks.contains(drink),
                  firstRange(personalWords, drink) == nil else { return nil }
            return (drink, shape.terse)
        }
        return nil
    }

    /// Per-record words and folded name parts, worked out once per database
    /// so a lookup never re-tokenizes all 450 records.
    struct Index: Sendable {
        let db: CaffeineDatabase
        let entryTokens: [Set<String>]
        let nameParts: [[String]]
        let idf: [String: Double]
        let byID: [String: Int]

        init(_ db: CaffeineDatabase) {
            self.db = db
            entryTokens = db.entries.map(DrinkPhotoMatcher.entryTokens)
            nameParts = db.entries.map { entry in
                [entry.name, entry.brand ?? ""]
                    .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",()")) }
                    .map { CaffeineContentQuestion.fold($0).trimmingCharacters(in: .whitespaces) }
            }
            var counts: [String: Int] = [:]
            for words in entryTokens { for word in words { counts[word, default: 0] += 1 } }
            let n = Double(max(db.entries.count, 1))
            idf = counts.mapValues { log(1 + n / Double($0)) }
            byID = Dictionary(db.entries.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        }

        /// `TypedDrinkEntry.confidentBrand`, on the precomputed words.
        func confidentBrand(_ phrase: String) -> TypedDrinkEntry.BrandMatch {
            let query = DrinkPhotoMatcher.tokens(phrase)
            guard !query.isEmpty else { return .none }
            let weight: (Set<String>) -> Double = { $0.reduce(0) { $0 + (idf[$1] ?? 1) } }
            let queryWeight = weight(query)
            let ranked = entryTokens.indices.compactMap { i -> (entry: CaffeineDatabase.Entry, score: Double)? in
                guard query.isSubset(of: entryTokens[i]) else { return nil }
                return (db.entries[i], queryWeight / max(weight(entryTokens[i]), .leastNonzeroMagnitude))
            }.sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.id < $1.entry.id }
            guard let first = ranked.first else { return .none }
            guard first.score >= 0.5, first.score - (ranked.dropFirst().first?.score ?? 0) >= DrinkPhotoMatcher.confidentMargin else { return .several }
            return .one(first.entry)
        }

        func names(_ entry: CaffeineDatabase.Entry, _ drink: String) -> Bool {
            guard let i = byID[entry.id] else { return false }
            return CaffeineContentQuestion.namesAny(nameParts[i], CaffeineContentQuestion.fold(drink))
        }
    }

    static func lookup(_ drink: String, db: CaffeineDatabase) -> Answer { lookup(drink, index: Index(db)) }

    static func lookup(_ drink: String, index: Index) -> Answer {
        let db = index.db
        if let plain = noCaffeineName(drink) { return .noCaffeine(drink: plain) }
        let presetRecord = TypedDrinkEntry.presetPhrases[drink].flatMap { TypedDrinkEntry.presetServings[$0]?.usdaEntryID }
        if let id = TypedDrinkEntry.genericPhrases[drink]?.id ?? presetRecord, let i = index.byID[id],
           let answer = found(db.entries[i], drink: drink, db: db) {
            return answer
        }
        if let brand = DrinkPhotoMatcher.unrecordedBrand(in: drink) { return .notInDatabase(drink: brand) }
        // A record counts only when the words name it, not a different
        // drink that contains them ("beer" is not Barq's Root Beer).
        let phrase = fold(drink)
        switch index.confidentBrand(drink) {
        case .one(let entry) where index.names(entry, drink):
            return found(entry, drink: entry.displayName, db: db) ?? .notInDatabase(drink: drink)
        case .several where index.nameParts.contains(where: { namesAny($0, phrase) }):
            return .several(drink: drink)
        default:
            return .notInDatabase(drink: drink)
        }
    }

    /// The no-caffeine list's name for the phrase, singular ("beers" → "beer").
    static func noCaffeineName(_ drink: String) -> String? {
        if noCaffeineDrinks.contains(drink) { return drink }
        if drink.hasSuffix("s"), noCaffeineDrinks.contains(String(drink.dropLast())) { return String(drink.dropLast()) }
        return nil
    }

    /// The drink's words start the record's name, its brand, a parenthetical
    /// or a comma-separated part: "red bull" names "Energy drink (Red Bull)"
    /// and "Energy drink, RED BULL"; "beer" doesn't name "Root Beer".
    static func names(_ entry: CaffeineDatabase.Entry, _ drink: String) -> Bool {
        let parts = [entry.name, entry.brand ?? ""]
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",()")) }
            .map { fold($0).trimmingCharacters(in: .whitespaces) }
        return namesAny(parts, fold(drink))
    }

    static func namesAny(_ parts: [String], _ phrase: String) -> Bool {
        parts.contains { part in
            part == phrase || part.hasPrefix(phrase + " ") || part.hasPrefix(phrase + "'")
        }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func found(_ entry: CaffeineDatabase.Entry, drink: String, db: CaffeineDatabase) -> Answer? {
        let serving = entry.servings.first(where: { $0.label.contains("8 fl oz") })
            ?? entry.servings.first(where: { $0.label != "1 fl oz" })
            ?? entry.servings.first
        guard let serving else { return nil }
        let source = (db.source(for: entry)?.shortName ?? entry.source) + " · " + entry.reference
        return .found(drink: drink, mg: serving.mg, serving: serving.label, source: source)
    }

    static func capture(_ regex: NSRegularExpression, _ text: String) -> String? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func firstRange(_ regex: NSRegularExpression, _ text: String) -> Range<String.Index>? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)).flatMap { Range($0.range, in: text) }
    }

    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
