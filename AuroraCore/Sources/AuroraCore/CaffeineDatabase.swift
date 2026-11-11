import Foundation

/// Aurora's bundled, offline caffeine reference. Every value is copied from a
/// USDA FoodData Central record (public domain, CC0 1.0) by
/// `scripts/build_caffeine_db.py`, or, for named brands USDA lacks, from the
/// maker's own website or label, merged by
/// `scripts/merge-manufacturer-caffeine.py` (page, date, serving and quote in
/// docs/caffeine-brands-provenance.json). Nothing here is estimated by a model.
/// A serving's mg is the record's caffeine per 100 g (or per 100 mL for label
/// data) times that record's own portion size, rounded to a whole mg.
public struct CaffeineDatabase: Codable, Equatable, Sendable {
    public struct Source: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let release: String
        public let license: String
        /// The source's site; empty for "manufacturer", whose records each carry their own page.
        public let url: String
        public let citation: String

        /// The name on the card's one-line source: "USDA" or "Manufacturer".
        public var shortName: String { name.hasPrefix("USDA") ? "USDA" : name }
    }
    public struct Serving: Codable, Equatable, Sendable {
        public let label: String
        public let amount: Double
        /// "g" (FNDDS/SR portion weight) or "mL" (Branded label serving).
        public let unit: String
        public let mg: Int
    }
    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        /// USDA FoodData Central id; `nil` for non-USDA records, which carry `url`.
        public let fdcId: Int?
        public let source: String
        public let name: String
        public let brand: String?
        public let category: String
        /// Caffeine mg per 100 of `basis`.
        public let per100: Double
        /// "g" or "mL".
        public let basis: String
        /// The record's own "1 fl oz" portion weight, when it has one. Only
        /// then can a label volume be converted for a gram-based record.
        public let gramsPerFlOz: Double?
        public let servings: [Serving]
        public let gtin: String?
        /// The page this record was copied from, for non-USDA records.
        public let url: String?
        /// When `url` was read, "yyyy-MM-dd".
        public let retrieved: String?

        /// "FDC 12345", or the source page without "https://www.".
        public var reference: String {
            if let fdcId { return "FDC \(fdcId)" }
            guard let url else { return id }
            return url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "www.", with: "")
        }

        /// A maker's published number holds only for the exact serving it was
        /// published for: never scaled to another size (CPO, Nov 10).
        public var publishedServingsOnly: Bool { source == "manufacturer" }

        public var displayName: String {
            guard let brand, !name.localizedCaseInsensitiveContains(brand) else { return name }
            return brand + " · " + name
        }
    }

    public let schema: Int
    public let version: String
    public let notice: String
    public let sources: [Source]
    public let entries: [Entry]

    public enum LoadError: Error, Equatable { case missing, unsupportedSchema(Int), invalid(String) }

    /// Decodes and validates. Any entry whose servings are not reproducible
    /// from its own per-100 value fails the whole load: a database that does
    /// not check out is not used at all.
    public static func load(from data: Data) throws -> CaffeineDatabase {
        let db = try JSONDecoder().decode(CaffeineDatabase.self, from: data)
        guard db.schema == 1 else { throw LoadError.unsupportedSchema(db.schema) }
        let ids = Set(db.sources.map(\.id))
        var seen = Set<String>()
        for entry in db.entries {
            guard seen.insert(entry.id).inserted else { throw LoadError.invalid("duplicate \(entry.id)") }
            guard ids.contains(entry.source) else { throw LoadError.invalid("unknown source for \(entry.id)") }
            // Every record names where it came from: a USDA id, or an https
            // source page and the date it was read.
            guard entry.fdcId != nil || (entry.retrieved != nil && entry.url != nil),
                  entry.url.map({ $0.hasPrefix("https://") }) ?? true else {
                throw LoadError.invalid("no provenance for \(entry.id)")
            }
            guard entry.per100.isFinite, entry.per100 > 0, ["g", "mL"].contains(entry.basis) else { throw LoadError.invalid("bad basis \(entry.id)") }
            for serving in entry.servings {
                guard serving.mg >= 1, serving.mg <= 1999, serving.unit == entry.basis,
                      serving.mg == Int((entry.per100 * serving.amount / 100).rounded()) else {
                    throw LoadError.invalid("serving mismatch \(entry.id)")
                }
            }
        }
        return db
    }

    /// The copy shipped inside AuroraCore. `nil` only if the bundle is damaged.
    public static let bundled: CaffeineDatabase? = {
        guard let url = Bundle.module.url(forResource: "caffeine-db", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? load(from: data)
    }()

    public func source(for entry: Entry) -> Source? { sources.first { $0.id == entry.source } }

    /// What the (i) button on the photo card shows: who the amount came
    /// from, and a link to the source: USDA FoodData Central, or the maker's
    /// page the amount was copied from.
    public struct Credit: Equatable, Sendable {
        public struct Link: Equatable, Sendable { public let title: String; public let url: String }
        public let title: String
        public let lines: [String]
        public let links: [Link]
        public init(title: String, lines: [String], links: [Link]) { self.title = title; self.lines = lines; self.links = links }
    }
    public static let creditTitle = "Caffeine Source"

    public func credit(for entry: Entry) -> Credit? {
        guard let source = source(for: entry) else { return nil }
        if source.id == "manufacturer" {
            var lines = ["The caffeine amount for this drink is from its maker’s own website or label."]
            if let retrieved = entry.retrieved { lines.append("Retrieved \(Self.displayDate(retrieved)).") }
            let links = entry.url.map { [Credit.Link(title: "View Source Page", url: $0)] } ?? []
            return Credit(title: Self.creditTitle, lines: lines, links: links)
        }
        return Credit(title: Self.creditTitle,
                      lines: ["The caffeine amount for this drink is from \(source.name), released \(source.release). \(source.license)."],
                      links: [.init(title: "Visit USDA FoodData Central", url: source.url)])
    }

    /// "2026-11-10" -> "Nov 10, 2026"; any other text is shown as is.
    static func displayDate(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard parts.count == 3, (1...12).contains(parts[1]) else { return day }
        return "\(months[parts[1] - 1]) \(parts[2]), \(parts[0])"
    }
    public func entry(id: String) -> Entry? { entries.first { $0.id == id } }

    /// Exact barcode lookup. UPC-A, EAN-13 and GTIN-14 forms of one code
    /// differ only by leading zeros.
    public func entry(gtin code: String) -> Entry? {
        let key = Self.gtinKey(code)
        guard !key.isEmpty else { return nil }
        return entries.first { $0.gtin.map(Self.gtinKey) == key }
    }
    static func gtinKey(_ code: String) -> String {
        let digits = code.filter(\.isNumber)
        guard digits.count >= 8 else { return "" }
        return String(digits.drop { $0 == "0" })
    }

    /// Caffeine for a volume read from the label, derived only from the
    /// record: per 100 mL directly, or via the record's own fl oz weight.
    /// Never for a maker's record, whose number holds for its serving only.
    /// `nil` when the record gives no way to convert, so the person picks a
    /// listed serving instead.
    public func mg(for entry: Entry, volume: Volume) -> Int? {
        guard !entry.publishedServingsOnly else { return nil }
        let base: Double
        switch entry.basis {
        case "mL": base = volume.milliliters
        case "g":
            guard let perFlOz = entry.gramsPerFlOz, perFlOz > 0 else { return nil }
            base = volume.milliliters / Volume.mlPerFlOz * perFlOz
        default: return nil
        }
        let mg = Int((entry.per100 * base / 100).rounded())
        return (1...1999).contains(mg) ? mg : nil
    }
}

/// A container volume read from label text.
public struct Volume: Equatable, Sendable {
    public static let mlPerFlOz = 29.5735
    public let milliliters: Double
    /// The text it was read from, shown back to the person.
    public let text: String

    public init(milliliters: Double, text: String) { self.milliliters = milliliters; self.text = text }

    public var label: String {
        let floz = milliliters / Self.mlPerFlOz
        return "\(Self.trim(floz)) fl oz (\(Int(milliliters.rounded())) mL)"
    }
    static func trim(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    /// Volumes printed on a label, e.g. "12 FL OZ (355 mL)", "16.9 fl. oz",
    /// "250ml", "1 L". A bare "oz" on a drink label is read as fluid ounces;
    /// the confirmation card shows the text so the person can correct it.
    public static func parse(_ text: String) -> [Volume] {
        let pattern = #"(?i)(\d{1,4}(?:[.,]\d{1,2})?)\s*(fl\.?\s*oz\.?|fluid\s+ounces?|floz|oz\.?|ml|millilit(?:er|re)s?|l|lit(?:er|re)s?)(?![a-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var found: [Volume] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let numberRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text),
                  let whole = Range(match.range, in: text),
                  let number = Double(text[numberRange].replacingOccurrences(of: ",", with: ".")) else { continue }
            let unit = text[unitRange].lowercased().replacingOccurrences(of: " ", with: "")
            let ml: Double
            if unit.hasPrefix("m") { ml = number }
            else if unit.hasPrefix("l") { ml = number * 1000 }
            else { ml = number * mlPerFlOz }
            // A drink container, not a nutrition-panel line or a typo.
            guard ml >= 30, ml <= 2000 else { continue }
            let volume = Volume(milliliters: ml, text: String(text[whole]))
            // "12 FL OZ (355 mL)" is one container, not two.
            if !found.contains(where: { abs($0.milliliters - ml) / ml < 0.03 }) { found.append(volume) }
        }
        return found
    }
}
