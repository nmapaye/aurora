import Foundation

/// A record that was actually entered or imported, copied at capture and
/// shown beside the modeled curve. Never derived from the model.
public struct EnergyObservation: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case caffeine, sleep }

    public var id: String
    public var kind: Kind
    public var source: EnergyInputSource
    /// Caffeine: when it was recorded. Sleep: its start.
    public var start: Millis
    /// Caffeine: equal to `start`. Sleep: its end.
    public var end: Millis
    public var mg: Double?
}

/// A completed Reaction Test, copied at capture. Shown apart from the model.
public struct EnergyReaction: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var completedAt: Millis
    public var score: Int
    public var rating: String
    public var sample: Bool
}

/// Everything an energy card shows, captured once. Old cards keep this
/// exactly; Refresh captures a new one.
public struct EnergySnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let scaleNote = "Modeled, 0–100."
    public static let separateNote = "Your ratings and Reaction Tests, as recorded."

    public var version: Int
    public var estimate: EnergyEstimate
    /// Present on the 24-hour card only.
    public var projection: EnergyProjection?
    /// Records, ratings and tests are listed from here to capture.
    public var windowStart: Millis
    /// Sleep and caffeine records known at capture, oldest first.
    public var observations: [EnergyObservation]
    /// Self-rated check-ins, newest first.
    public var checkIns: [EnergyCheckIn]
    /// Reaction Tests, newest first.
    public var reactions: [EnergyReaction]

    public static func capture(state: AppState, now: Millis, clock: LocalClock, includeProjection: Bool) -> EnergySnapshot {
        let inputs = EstimateInputs(prefs: state.prefs, clock: clock)
        let known = EnergyProjection.knownRecords(doses: state.doses, sleeps: state.sleeps, at: now)
        // One input set for the headline, evidence, observations and the
        // curve: records known at capture. The scalar model is unchanged; it
        // is only given these records.
        let estimate = EnergyEstimate.capture(at: now, doses: known.doses, sleeps: known.sleeps, inputs: inputs)
        let projection = includeProjection ? EnergyProjection.build(now: now, doses: state.doses, sleeps: state.sleeps, inputs: inputs) : nil
        let windowStart = projection?.points.first?.t ?? now - dayMs
        let caffeine = known.doses.filter { $0.timestamp >= windowStart }.map {
            EnergyObservation(id: $0.id, kind: .caffeine, source: .of(doseID: $0.id), start: $0.timestamp, end: $0.timestamp, mg: $0.mg)
        }
        let sleep = known.sleeps.filter { $0.end > windowStart }.map {
            EnergyObservation(id: $0.id, kind: .sleep, source: .of(sleepID: $0.id), start: $0.start, end: $0.end, mg: nil)
        }
        return EnergySnapshot(
            version: currentVersion,
            estimate: estimate,
            projection: projection,
            windowStart: windowStart,
            observations: (caffeine + sleep).sorted { ($0.start, $0.id) < ($1.start, $1.id) },
            checkIns: state.energyCheckIns.filter { $0.recordedAt >= windowStart && $0.recordedAt <= now }
                .sorted { ($0.recordedAt, $0.id) > ($1.recordedAt, $1.id) },
            reactions: state.vigilanceSessions.filter { $0.completedAt >= windowStart && $0.completedAt <= now }
                .sorted { ($0.completedAt, $0.id) > ($1.completedAt, $1.id) }
                .map { EnergyReaction(id: $0.id, completedAt: $0.completedAt, score: $0.score, rating: $0.rating.rawValue, sample: RecordID.isSample($0.id)) }
        )
    }

    /// Recorded sleep intervals with overlaps joined, as the model counts
    /// them. Equal or overlapping records draw once.
    public var mergedSleep: [(start: Millis, end: Millis)] {
        var merged: [(start: Millis, end: Millis)] = []
        for item in observations.filter({ $0.kind == .sleep }).sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, item.start <= last.end {
                merged[merged.count - 1].end = max(last.end, item.end)
            } else {
                merged.append((item.start, item.end))
            }
        }
        return merged
    }

    public var includesSample: Bool {
        estimate.includesSample || observations.contains { $0.source == .sample } || projection?.points.contains(where: \.includesSample) == true
    }
}

extension EnergyContribution.Kind {
    public var label: String {
        switch self {
        case .baseline: "Model starting point"
        case .timeOfDay: "Time of day · generic curve"
        case .caffeine: "Estimated active caffeine"
        case .sleepDebt: "Recorded sleep against your goal"
        case .inertia: "Shortly after waking"
        }
    }
}

extension EnergyContribution {
    /// Signed whole points on the model scale: "+12", "−8", "0".
    public var pointsText: String {
        let value = jsRoundInt(points)
        return value > 0 ? "+\(value)" : (value < 0 ? "−\(-value)" : "0")
    }
}

extension EnergyProjection.PointKind {
    public var label: String {
        switch self {
        case .modeledPast: "Modeled from records known at capture"
        case .current: "Captured now"
        case .projected: "Projected · assumes no further sleep or caffeine"
        }
    }
}

/// A check-in being reviewed. Its id is fixed when the review opens, so a
/// repeated Save can never add a second record.
public struct EnergyCheckInDraft: Codable, Equatable, Sendable {
    public var id: String
    /// Nil until the person chooses one; nothing is preselected.
    public var rating: Int?
    public var recordedAt: Millis
    public var note: String
    /// The saved check-in this review corrects.
    public var original: EnergyCheckIn?

    public init(id: String, rating: Int? = nil, recordedAt: Millis, note: String = "", original: EnergyCheckIn? = nil) {
        self.id = id
        self.rating = rating
        self.recordedAt = recordedAt
        self.note = note
        self.original = original
    }

    public static func new(now: Millis, rating: Int? = nil, entropy: String = RecordID.entropy()) -> EnergyCheckInDraft {
        EnergyCheckInDraft(id: RecordID.newEnergyCheckInID(now: now, entropy: entropy), rating: rating, recordedAt: now)
    }

    public static func editing(_ checkIn: EnergyCheckIn) -> EnergyCheckInDraft {
        EnergyCheckInDraft(id: checkIn.id, rating: checkIn.rating, recordedAt: checkIn.recordedAt, note: checkIn.note ?? "", original: checkIn)
    }

    public func validate(now: Millis) -> DraftValidation {
        guard let rating else { return .invalid("Choose a rating from 1 to 5.") }
        return EnergyCheckIn.validate(rating: rating, recordedAt: recordedAt, now: now)
    }

    public var checkIn: EnergyCheckIn? {
        guard let rating else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return EnergyCheckIn(id: id, recordedAt: recordedAt, rating: rating, note: trimmed.isEmpty ? nil : String(trimmed.prefix(500)))
    }
}

extension EnergyCheckIn {
    public static let sourceLabel = "Your rating"

    /// "4 · High"
    public var ratingText: String {
        "\(rating) · \(Self.label(forRating: rating) ?? "Not on the scale")"
    }
}

extension AppState {
    /// Replaces a saved check-in only if it is still exactly `original`.
    @discardableResult
    public mutating func replaceEnergyCheckIn(_ updated: EnergyCheckIn, expecting original: EnergyCheckIn, now: Millis) -> DraftValidation {
        let validation = updated.validate(now: now)
        guard validation == .valid else { return validation }
        guard updated.id == original.id, let index = energyCheckIns.firstIndex(where: { $0.id == original.id }),
              energyCheckIns[index] == original else {
            return .invalid("This check-in changed or was removed. Review it again.")
        }
        energyCheckIns[index] = updated
        energyCheckIns = Self.stableSorted(energyCheckIns) { $0.recordedAt > $1.recordedAt }
        return .valid
    }

    /// Removes a check-in only if it is still exactly `expected`.
    @discardableResult
    public mutating func removeEnergyCheckIn(_ expected: EnergyCheckIn) -> Bool {
        guard energyCheckIns.contains(expected) else { return false }
        energyCheckIns.removeAll { $0.id == expected.id }
        return true
    }
}

extension Export {
    public static func energyCheckInsCSV(_ checkIns: [EnergyCheckIn], clock: LocalClock) -> String {
        let lines = AppState.stableSorted(checkIns.filter { $0.recordedAt.isFinite }) { $0.recordedAt < $1.recordedAt }.map {
            row([$0.id, clock.isoDay($0.recordedAt), isoTimestamp($0.recordedAt), "\($0.rating)", EnergyCheckIn.label(forRating: $0.rating) ?? "", $0.note ?? "", EnergyCheckIn.sourceLabel])
        }
        return (["id,local_date,datetime,rating,label,note,data_source"] + lines).joined(separator: "\n")
    }
}
