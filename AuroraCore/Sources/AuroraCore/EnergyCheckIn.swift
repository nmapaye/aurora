import Foundation

/// The person's own energy rating, recorded as entered. It is an
/// observation, not an estimate, and never feeds modeled alertness.
/// The rating is stored as a plain number so an out-of-range value can't
/// stop the whole state from decoding; `validate` guards new entries.
public struct EnergyCheckIn: Codable, Equatable, Hashable, Identifiable, Sendable {
    public static let scale = 1...5
    public static let scaleLabel = "Your energy, from 1 (very low) to 5 (very high)"
    public static let kindLabel = "Your rating."

    public var id: String
    public var recordedAt: Millis
    public var rating: Int
    public var note: String?

    public init(id: String, recordedAt: Millis, rating: Int, note: String? = nil) {
        self.id = id
        self.recordedAt = recordedAt
        self.rating = rating
        self.note = note
    }

    public static func label(forRating rating: Int) -> String? {
        switch rating {
        case 1: "Very low"
        case 2: "Low"
        case 3: "Moderate"
        case 4: "High"
        case 5: "Very high"
        default: nil
        }
    }

    public static func validate(rating: Int, recordedAt: Millis, now: Millis) -> DraftValidation {
        guard scale.contains(rating) else { return .invalid("Choose a rating from 1 to 5.") }
        guard recordedAt.isFinite, recordedAt <= now else { return .invalid("Time cannot be in the future.") }
        return .valid
    }

    public func validate(now: Millis) -> DraftValidation {
        guard !id.isEmpty else { return .invalid("This check-in has no id.") }
        return Self.validate(rating: rating, recordedAt: recordedAt, now: now)
    }
}
