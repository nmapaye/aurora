import Foundation

/// The "<n> mg" rule shared by the new text parsers (`TypedDrinkEntry`,
/// `CaffeineQuestion`). A token is read only when it's a plain number:
/// digits, optionally one decimal part. A sign, a digit group ("1,126"),
/// or a malformed number ("1.2.3") makes the whole token unusable, so the
/// caller asks again; it never drops a sign or a leading group to keep the
/// trailing digits.
public enum MgToken {
    public struct Match: Equatable, Sendable {
        public let range: Range<String.Index>
        /// Nil when the token isn't a plain number.
        public let value: Double?
    }

    /// The number token runs back over digits, separators and signs, so
    /// "-126mg" and "1,126mg" are seen whole, not as "126mg".
    static let pattern = #"(?<![0-9.,+\-−])([+\-−]?[0-9.,]*[0-9][0-9.,]*)\s*mg\b"#
    static let plain = #"^[0-9]+(\.[0-9]+)?$"#

    public static func matches(in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let whole = Range(match.range, in: text), let number = Range(match.range(at: 1), in: text) else { return nil }
            let token = String(text[number])
            let isPlain = token.range(of: plain, options: .regularExpression) != nil
            return Match(range: whole, value: isPlain ? Double(token) : nil)
        }
    }
}
