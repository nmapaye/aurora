import Foundation

/// Modeled alertness across 24 hours around the capture instant, every 30
/// minutes on the epoch's half-hour grid, plus the capture instant itself.
/// Every point is model output; none is measured data.
///
/// Only records known at capture are used: doses at or before it and sleep
/// that had ended by it. Points ahead of capture assume no further sleep or
/// caffeine, so they show the model's drift, not a forecast of the day.
public struct EnergyProjection: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let stepMs: Millis = 30 * minuteMs
    public static let pastSpanMs: Millis = 12 * hourMs
    public static let futureSpanMs: Millis = 12 * hourMs
    public static let futureAssumption = "Points after now assume no further sleep or caffeine is recorded."

    public enum PointKind: String, Codable, Sendable {
        /// Modeled from records known at capture.
        case modeledPast
        /// The capture instant.
        case current
        /// Modeled with no records added after capture.
        case projected
    }

    public struct Point: Codable, Equatable, Sendable {
        public var t: Millis
        public var kind: PointKind
        public var modeledScore: Int?
        public var includesSample: Bool

        public init(t: Millis, kind: PointKind, modeledScore: Int?, includesSample: Bool) {
            self.t = t
            self.kind = kind
            self.modeledScore = modeledScore
            self.includesSample = includesSample
        }
    }

    public var version: Int
    public var modelVersion: String
    public var capturedAt: Millis
    public var timeZoneIdentifier: String
    public var points: [Point]
    public var currentIndex: Int

    public var current: Point { points[currentIndex] }

    /// Records as known at `now`: nothing dated after it.
    public static func knownRecords(doses: [Dose], sleeps: [SleepSession], at now: Millis) -> (doses: [Dose], sleeps: [SleepSession]) {
        (doses.filter { $0.timestamp <= now }, sleeps.filter { $0.end <= now })
    }

    public static func build(
        now: Millis,
        doses: [Dose],
        sleeps: [SleepSession],
        inputs: EstimateInputs
    ) -> EnergyProjection {
        let known = knownRecords(doses: doses, sleeps: sleeps, at: now)
        let anchor = (now / stepMs).rounded(.down) * stepMs
        let first = anchor - pastSpanMs
        let count = Int(((pastSpanMs + futureSpanMs) / stepMs).rounded()) + 1
        var times = (0..<count).map { first + Double($0) * stepMs }
        if !times.contains(now) {
            times.insert(now, at: times.firstIndex { $0 > now } ?? times.endIndex)
        }
        let points = times.map { t -> Point in
            let estimate = EnergyEstimate.capture(at: t, doses: known.doses, sleeps: known.sleeps, inputs: inputs)
            let kind: PointKind = t < now ? .modeledPast : (t == now ? .current : .projected)
            return Point(t: t, kind: kind, modeledScore: estimate.modeledScore, includesSample: estimate.includesSample)
        }
        return EnergyProjection(
            version: currentVersion,
            modelVersion: EnergyEstimate.currentModelVersion,
            capturedAt: now,
            timeZoneIdentifier: inputs.clock.timeZone.identifier,
            points: points,
            currentIndex: points.firstIndex { $0.kind == .current } ?? 0
        )
    }
}
