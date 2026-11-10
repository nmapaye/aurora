import Foundation

/// What Apple's on-device frameworks saw in one drink photo. Built by the app
/// from Vision text recognition, barcode detection and image classification,
/// plus, on iOS 27, the on-device Foundation Model's short description.
/// Everything here is search evidence only: no number in it ever becomes a
/// caffeine amount. Amounts come from `CaffeineDatabase` entries.
public struct DrinkPhotoObservation: Equatable, Sendable {
    /// Lines of text Vision read from the label or cup.
    public var recognizedText: [String]
    /// Barcode payloads (UPC/EAN) Vision decoded.
    public var barcodes: [String]
    /// Vision image-classification identifiers with confidence 0...1.
    public var labels: [String: Double]
    /// Search words from an on-device model. Untrusted, and empty in the app
    /// today: no model reads the photo (see docs/drink-photo-logging.md).
    public var modelDrink: String
    public var modelBrand: String

    public init(recognizedText: [String] = [], barcodes: [String] = [], labels: [String: Double] = [:],
                modelDrink: String = "", modelBrand: String = "") {
        self.recognizedText = recognizedText; self.barcodes = barcodes; self.labels = labels
        self.modelDrink = modelDrink; self.modelBrand = modelBrand
    }

    public var isEmpty: Bool {
        recognizedText.isEmpty && barcodes.isEmpty && labels.isEmpty && modelDrink.isEmpty && modelBrand.isEmpty
    }
    /// Only text Vision actually read from the photo can supply a container
    /// size. The model's words never do.
    public var labelVolumes: [Volume] { Volume.parse(recognizedText.joined(separator: "\n")) }
}

public enum DrinkPhotoMatcher {
    public enum Reason: String, Equatable, Sendable { case barcode, text }
    public struct Candidate: Equatable, Sendable, Identifiable {
        public let entry: CaffeineDatabase.Entry
        public let score: Double
        public let reason: Reason
        public var id: String { entry.id }
    }
    public enum Result: Equatable, Sendable {
        /// Ranked candidates. The person always confirms one; `confident`
        /// only decides whether the first is preselected.
        case candidates([Candidate], confident: Bool)
        /// Nothing in the database matched well enough to suggest.
        case noMatch(String)
    }

    public static let minimumScore = 0.34
    public static let confidentScore = 0.7
    public static let confidentMargin = 0.15
    public static let limit = 5

    /// Vision classifier identifiers that name a drink kind. Other labels
    /// (cup, bottle, table...) are not drink evidence.
    static let labelWords: [String: String] = [
        "coffee": "coffee", "espresso": "espresso", "cappuccino": "cappuccino", "latte": "latte",
        "tea": "tea", "green_tea": "green tea", "matcha": "matcha", "iced_tea": "iced tea",
        "soda": "soda", "cola": "cola", "energy_drink": "energy drink", "hot_chocolate": "chocolate",
    ]

    public static func match(_ observation: DrinkPhotoObservation, in db: CaffeineDatabase) -> Result {
        for code in observation.barcodes {
            if let entry = db.entry(gtin: code) {
                return .candidates([Candidate(entry: entry, score: 1, reason: .barcode)], confident: true)
            }
        }
        var words = observation.recognizedText + [observation.modelDrink, observation.modelBrand]
        for (label, confidence) in observation.labels where confidence >= 0.3 {
            if let word = labelWords[label.lowercased()] { words.append(word) }
        }
        let query = tokens(words.joined(separator: " "))
        guard !query.isEmpty else {
            return .noMatch("Aurora couldn't read a drink name in this photo. Try a closer photo of the label, or choose the drink yourself.")
        }
        let idf = inverseFrequency(db)
        var scored: [Candidate] = []
        for entry in db.entries {
            let score = self.score(query: query, entry: entry, idf: idf)
            if score >= minimumScore { scored.append(Candidate(entry: entry, score: score, reason: .text)) }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.entry.id < $1.entry.id }
        let top = Array(scored.prefix(limit))
        guard let first = top.first else {
            return .noMatch("No drink in Aurora's caffeine database matched this photo. Search the database or enter the amount yourself.")
        }
        let margin = first.score - (top.dropFirst().first?.score ?? 0)
        return .candidates(top, confident: first.score >= confidentScore && margin >= confidentMargin)
    }

    /// Text search used when the person types a drink name on the card.
    public static func search(_ text: String, in db: CaffeineDatabase) -> [Candidate] {
        let query = tokens(text)
        guard !query.isEmpty else { return [] }
        let idf = inverseFrequency(db)
        return db.entries.compactMap { entry -> Candidate? in
            let s = score(query: query, entry: entry, idf: idf)
            return s >= minimumScore ? Candidate(entry: entry, score: s, reason: .text) : nil
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.id < $1.entry.id }
        .prefix(limit * 2).map { $0 }
    }

    static let stopWords: Set<String> = ["the", "and", "with", "of", "a", "an", "in", "to", "for", "or", "ns", "as",
                                         "type", "beverages", "beverage", "bottle", "can", "fl", "oz", "ml", "pack",
                                         "ready", "drink", "net", "contains", "company", "inc", "llc", "co"]

    static func tokens(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let parts = folded.split { !$0.isLetter }.map(String.init)
        return Set(parts.filter { $0.count >= 2 && !stopWords.contains($0) })
    }

    static func entryTokens(_ entry: CaffeineDatabase.Entry) -> Set<String> {
        tokens(entry.name + " " + (entry.brand ?? ""))
    }

    static func inverseFrequency(_ db: CaffeineDatabase) -> [String: Double] {
        var counts: [String: Int] = [:]
        for entry in db.entries { for token in entryTokens(entry) { counts[token, default: 0] += 1 } }
        let n = Double(max(db.entries.count, 1))
        return counts.mapValues { log(1 + n / Double($0)) }
    }

    /// How much of the entry's distinctive vocabulary the photo shows. OCR
    /// often drops or swaps one letter, so long tokens also match at edit
    /// distance one, at a discount.
    static func score(query: Set<String>, entry: CaffeineDatabase.Entry, idf: [String: Double]) -> Double {
        let words = entryTokens(entry)
        guard !words.isEmpty else { return 0 }
        var total = 0.0, matched = 0.0
        for word in words {
            let weight = idf[word] ?? 1
            total += weight
            if query.contains(word) { matched += weight }
            else if word.count >= 5, query.contains(where: { $0.count >= 5 && editDistanceAtMostOne($0, word) }) { matched += weight * 0.8 }
        }
        var score = matched / total
        // A brand printed on the label is the strongest text evidence.
        if let brand = entry.brand {
            let brandWords = tokens(brand)
            if !brandWords.isEmpty, brandWords.isSubset(of: query) { score = min(1, score + 0.15) }
        }
        return score
    }

    static func editDistanceAtMostOne(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > 1 { return false }
        var i = 0, j = 0, edits = 0
        while i < x.count && j < y.count {
            if x[i] == y[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if x.count > y.count { i += 1 } else if y.count > x.count { j += 1 } else { i += 1; j += 1 }
        }
        return edits + (x.count - i) + (y.count - j) <= 1
    }
}

/// The editable confirmation card behind photo logging. Nothing is saved
/// until the person taps Save on a card that names a database entry and a
/// serving (or types their own amount). Autosave does not exist here.
public struct DrinkPhotoConfirmation: Equatable, Sendable {
    public static let autosaveEnabled = false
    /// Shown when no database record is chosen or found.
    public static let notInDatabaseTitle = "Not in Database"
    /// The line under Not in Database while the person types the drink in.
    public static let manualEntryLine = "Enter the caffeine amount yourself, from the label or menu. Aurora doesn’t fill it in."

    public enum ServingChoice: Equatable, Sendable {
        /// One of the entry's listed servings.
        case listed(Int)
        /// A container size Vision read from the label.
        case label(Volume)
    }
    public struct Amount: Equatable, Sendable {
        public let mg: Int
        /// Where the number came from, shown on the card and kept in the note.
        public let provenance: String
        public let edited: Bool
    }

    public private(set) var candidates: [DrinkPhotoMatcher.Candidate]
    public private(set) var labelVolumes: [Volume]
    public private(set) var entry: CaffeineDatabase.Entry?
    public private(set) var serving: ServingChoice?
    /// A whole-mg amount the person typed over the database value.
    public private(set) var typedMg: String?
    /// Set while the person enters a drink the database doesn't have; the
    /// name they type. Nil when a database record is in use.
    public private(set) var manualName: String?
    public var timestamp: Millis
    public let noMatchMessage: String?

    public init(result: DrinkPhotoMatcher.Result, observation: DrinkPhotoObservation, timestamp: Millis) {
        self.timestamp = timestamp
        labelVolumes = observation.labelVolumes
        switch result {
        case .candidates(let list, let confident):
            candidates = list; noMatchMessage = nil
            if confident, let first = list.first { entry = first.entry }
        case .noMatch(let message):
            candidates = []; noMatchMessage = message
        }
        if let entry { serving = Self.defaultServing(entry, volumes: labelVolumes) }
    }

    /// Choosing a different drink clears any amount the person typed.
    public mutating func select(_ entry: CaffeineDatabase.Entry) {
        self.entry = entry
        typedMg = nil
        manualName = nil
        serving = Self.defaultServing(entry, volumes: labelVolumes)
        if !candidates.contains(where: { $0.entry.id == entry.id }) {
            candidates.insert(.init(entry: entry, score: 0, reason: .text), at: 0)
        }
    }
    public mutating func choose(_ choice: ServingChoice) { serving = choice; typedMg = nil }
    public mutating func type(mg text: String) { typedMg = text }
    public mutating func clearTypedAmount() { typedMg = nil }

    /// Nothing in the database matched, or the person chose to: they name
    /// the drink and type the amount. No database number is used or shown.
    public mutating func enterManually() {
        entry = nil; serving = nil
        manualName = manualName ?? ""
        typedMg = typedMg ?? ""
    }
    /// Back to the photo's matches; the typed name and amount are dropped.
    public mutating func leaveManualEntry() { manualName = nil; typedMg = nil }
    public mutating func name(_ text: String) { if manualName != nil { manualName = text } }

    /// No database record is in use: nothing matched, or the person is
    /// entering the drink themselves.
    public var isNotInDatabase: Bool { manualName != nil || (entry == nil && candidates.isEmpty) }

    /// A label volume is preselected only when the entry can convert it and
    /// one of the entry's own listed servings is the same size, so a misread
    /// label ("71 FL OZ" for "12 FL OZ") is never picked for the person. One
    /// listed serving is preselected only when the photo showed no size.
    /// Otherwise the person picks.
    static func defaultServing(_ entry: CaffeineDatabase.Entry, volumes: [Volume]) -> ServingChoice? {
        if volumes.count == 1, let volume = volumes.first, convertible(entry), corroborated(volume, by: entry) { return .label(volume) }
        if volumes.isEmpty, entry.servings.count == 1 { return .listed(0) }
        return nil
    }
    /// Whether a listed serving names a container within 3% of `volume`,
    /// read from its label text ("1 can (8.4 fl oz)") or its mL amount.
    static func corroborated(_ volume: Volume, by entry: CaffeineDatabase.Entry) -> Bool {
        entry.servings.contains { serving in
            var sizes = Volume.parse(serving.label).map(\.milliliters)
            if serving.unit == "mL" { sizes.append(serving.amount) }
            return sizes.contains { abs($0 - volume.milliliters) / volume.milliliters < 0.03 }
        }
    }
    static func convertible(_ entry: CaffeineDatabase.Entry) -> Bool {
        entry.basis == "mL" || entry.gramsPerFlOz != nil
    }

    /// Label sizes this entry can convert. Others are hidden, not guessed.
    public var usableLabelVolumes: [Volume] {
        guard let entry else { return [] }
        return Self.convertible(entry) ? labelVolumes : []
    }

    public func amount(db: CaffeineDatabase) -> Amount? {
        if let typedMg {
            guard let value = Int(typedMg.trimmingCharacters(in: .whitespaces)), (1...1999).contains(value) else { return nil }
            if manualName != nil { return Amount(mg: value, provenance: "Typed by you · not in Aurora’s database", edited: true) }
            let original = databaseAmount(db: db).map { " (database: \($0.mg) mg)" } ?? ""
            return Amount(mg: value, provenance: "Typed by you" + original, edited: true)
        }
        return databaseAmount(db: db)
    }

    func databaseAmount(db: CaffeineDatabase) -> Amount? {
        guard let entry, let serving, let source = db.source(for: entry) else { return nil }
        switch serving {
        case .listed(let index):
            guard entry.servings.indices.contains(index) else { return nil }
            let s = entry.servings[index]
            return Amount(mg: s.mg, provenance: "\(source.name) · FDC \(entry.fdcId) · \(s.label)", edited: false)
        case .label(let volume):
            guard let mg = db.mg(for: entry, volume: volume) else { return nil }
            return Amount(mg: mg, provenance: "\(source.name) · FDC \(entry.fdcId) · \(volume.label) from label \"\(volume.text)\"", edited: false)
        }
    }

    /// What the card asks when it cannot offer Save yet. `nil` means ready.
    public func clarification(db: CaffeineDatabase) -> String? {
        if let manualName {
            if manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "What is the drink called?" }
            if amount(db: db) == nil { return "Enter a whole amount between 1 and 1999 mg." }
            return nil
        }
        if entry == nil {
            if let noMatchMessage, candidates.isEmpty { return noMatchMessage }
            return "Which drink is this? Pick the closest match."
        }
        if let typedMg, amount(db: db) == nil {
            return "Enter a whole amount between 1 and 1999 mg."
        }
        if serving == nil, typedMg == nil { return "What size was it? Pick a serving." }
        if amount(db: db) == nil { return "This size can't be converted from the database entry. Pick a listed serving." }
        return nil
    }

    /// The draft the person explicitly saves. `nil` until the card is
    /// complete and valid; there is no path that saves without this call.
    public func draft(db: CaffeineDatabase, now: Millis) -> CustomDoseDraft? {
        guard clarification(db: db) == nil, let amount = amount(db: db) else { return nil }
        let typedName = manualName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name = typedName ?? entry?.displayName else { return nil }
        let source = name.count > 60 ? String(name.prefix(59)) + "…" : name
        let draft = CustomDoseDraft(mg: String(amount.mg), source: source, timestamp: timestamp, note: "Photo · " + amount.provenance)
        return CaffeineLog.validate(draft, now: now) == .valid ? draft : nil
    }
}
