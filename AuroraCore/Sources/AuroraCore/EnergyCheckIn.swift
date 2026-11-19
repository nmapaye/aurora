import Foundation

/// The scale a check-in was recorded on. New check-ins are the
/// self-reported Karolinska Sleepiness Scale; earlier builds recorded a 1–5
/// energy rating, which stays readable as it was entered and is never
/// converted to KSS.
public enum CheckInScale: String, Codable, Sendable, CaseIterable {
    /// Self-reported KSS, version B: 1 (extremely alert) to 9 (very
    /// sleepy). Higher means sleepier.
    case kss
    /// Pre-KSS 1 (very low) to 5 (very high) energy rating.
    case energy5

    public var range: ClosedRange<Int> { self == .kss ? 1...9 : 1...5 }

    public var name: String { self == .kss ? "KSS" : "Energy" }

    public var invalidMessage: String { "Choose a rating from \(range.lowerBound) to \(range.upperBound)." }

    /// The anchor for every point. KSS wording is version B from Åkerstedt
    /// Miley, Kecklund & Åkerstedt (2016), sentence capitalization only.
    public func label(forRating rating: Int) -> String? {
        switch self {
        case .kss:
            switch rating {
            case 1: "Extremely alert"
            case 2: "Very alert"
            case 3: "Alert"
            case 4: "Rather alert"
            case 5: "Neither alert nor sleepy"
            case 6: "Some signs of sleepiness"
            case 7: "Sleepy, but no effort to keep awake"
            case 8: "Sleepy, some effort to keep awake"
            case 9: "Very sleepy, great effort keeping awake, fighting sleep"
            default: nil
            }
        case .energy5:
            switch rating {
            case 1: "Very low"
            case 2: "Low"
            case 3: "Moderate"
            case 4: "High"
            case 5: "Very high"
            default: nil
            }
        }
    }
}

/// The person's own rating, recorded as entered. It is an observation, not
/// an estimate: Aurora never calculates or predicts it, and it never feeds
/// modeled alertness. The rating is stored as a plain number so an
/// out-of-range value can't stop the whole state from decoding; `validate`
/// guards new entries.
public struct EnergyCheckIn: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// The scale new check-ins use.
    public static let scale = CheckInScale.kss.range
    public static let scaleLabel = "How sleepy have you felt in the last 5 minutes?"
    /// Identifies the check-in card's summary; not shown.
    public static let kindLabel = "Your rating."
    /// Shown behind the card's info button.
    public static let kssInfo = "Karolinska Sleepiness Scale (KSS), self-reported. Choose the number that best matches how you felt over the last 5 minutes; higher means sleepier. Aurora records what you choose and never calculates it. Labels: version B, Åkerstedt Miley A, Kecklund G, Åkerstedt T (2016), Comparing two versions of the Karolinska Sleepiness Scale, Sleep and Biological Rhythms, doi:10.1007/s41105-016-0048-8, CC BY 4.0."

    public var id: String
    public var recordedAt: Millis
    public var rating: Int
    public var note: String?
    /// Nil in files from builds before KSS: those ratings were 1–5 energy.
    /// New check-ins always write `.kss`.
    public var scale: CheckInScale?

    public init(id: String, recordedAt: Millis, rating: Int, note: String? = nil, scale: CheckInScale? = .kss) {
        self.id = id
        self.recordedAt = recordedAt
        self.rating = rating
        self.note = note
        self.scale = scale
    }

    /// The scale this rating was entered on; nil reads as the old energy scale.
    public var recordedScale: CheckInScale { scale ?? .energy5 }

    public var interpretation: String? { recordedScale.label(forRating: rating) }

    /// A KSS anchor.
    public static func label(forRating rating: Int) -> String? {
        CheckInScale.kss.label(forRating: rating)
    }

    public static func validate(rating: Int, recordedAt: Millis, now: Millis, scale: CheckInScale = .kss) -> DraftValidation {
        guard scale.range.contains(rating) else { return .invalid(scale.invalidMessage) }
        guard recordedAt.isFinite, recordedAt <= now else { return .invalid("Time cannot be in the future.") }
        return .valid
    }

    public func validate(now: Millis) -> DraftValidation {
        guard !id.isEmpty else { return .invalid("This check-in has no id.") }
        return Self.validate(rating: rating, recordedAt: recordedAt, now: now, scale: recordedScale)
    }
}
