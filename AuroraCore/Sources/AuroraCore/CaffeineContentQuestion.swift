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

    /// Whole-question shapes; capture group 1 is the drink.
    static let patterns = [
        #"^how much caffeine (?:is |are )?(?:there )?(?:in|does|do) (.+?)(?: have| has| contain| contains)?$"#,
        #"^(?:does|do) (.+?) (?:have|has|contain|contains) (?:any )?caffeine$"#,
        #"^is there (?:any )?caffeine in (.+)$"#,
        #"^what(?:'s| is) the caffeine(?: content| amount)? (?:in|of) (.+)$"#,
        #"^caffeine (?:in|content of) (.+)$"#,
    ]
    /// Words that make it a question about the person, a time or a dose.
    static let personalWords = #"\b(i|i'm|i've|me|my|you|your|left|today|tonight|now|body|system|blood|day|week|yesterday|tomorrow|bed ?time|should|safe|limit)\b"#
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
    static let leadingFiller = #"^(?:(?:a|one) (?:cup|can|glass|bottle|shot) of|(?:cup|can|glass|bottle|shot) of|a|an|the|one|some)\s+"#

    /// The answer, or nil when the text isn't a question about a drink's caffeine.
    public static func answer(_ input: String, db: CaffeineDatabase?) -> Answer? {
        guard let db, let drink = drink(in: input) else { return nil }
        return lookup(drink, db: db)
    }

    /// The drink a content question names, lowercased, without articles.
    public static func drink(in input: String) -> String? {
        var text = input.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, "?.!".contains(last) { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 120 else { return nil }
        for pattern in patterns {
            guard let captured = capture(pattern, text) else { continue }
            var drink = captured.trimmingCharacters(in: .whitespaces)
            if let filler = drink.range(of: leadingFiller, options: .regularExpression) { drink.removeSubrange(filler) }
            drink = drink.trimmingCharacters(in: .whitespaces)
            guard !drink.isEmpty, drink.count <= 40,
                  !drink.contains(where: \.isNumber) || noCaffeineDrinks.contains(drink),
                  drink.range(of: personalWords, options: .regularExpression) == nil else { return nil }
            return drink
        }
        return nil
    }

    static func lookup(_ drink: String, db: CaffeineDatabase) -> Answer {
        if let plain = noCaffeineName(drink) { return .noCaffeine(drink: plain) }
        let presetRecord = TypedDrinkEntry.presetPhrases[drink].flatMap { TypedDrinkEntry.presetServings[$0]?.usdaEntryID }
        if let id = TypedDrinkEntry.genericPhrases[drink]?.id ?? presetRecord, let entry = db.entry(id: id),
           let answer = found(entry, drink: drink, db: db) {
            return answer
        }
        if let brand = DrinkPhotoMatcher.unrecordedBrand(in: drink) { return .notInDatabase(drink: brand) }
        // A record counts only when the words name it, not a different
        // drink that contains them ("beer" is not Barq's Root Beer).
        switch TypedDrinkEntry.confidentBrand(drink, in: db) {
        case .one(let entry) where names(entry, drink):
            return found(entry, drink: entry.displayName, db: db) ?? .notInDatabase(drink: drink)
        case .several where db.entries.contains(where: { names($0, drink) }):
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
        let fold: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        let phrase = fold(drink)
        let parts = [entry.name, entry.brand ?? ""]
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",()")) }
            .map { fold($0).trimmingCharacters(in: .whitespaces) }
        return parts.contains { part in
            part == phrase || part.hasPrefix(phrase + " ") || part.hasPrefix(phrase + "'")
        }
    }

    static func found(_ entry: CaffeineDatabase.Entry, drink: String, db: CaffeineDatabase) -> Answer? {
        let serving = entry.servings.first(where: { $0.label.contains("8 fl oz") })
            ?? entry.servings.first(where: { $0.label != "1 fl oz" })
            ?? entry.servings.first
        guard let serving else { return nil }
        let source = (db.source(for: entry)?.shortName ?? entry.source) + " · " + entry.reference
        return .found(drink: drink, mg: serving.mg, serving: serving.label, source: source)
    }

    static func capture(_ pattern: String, _ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
