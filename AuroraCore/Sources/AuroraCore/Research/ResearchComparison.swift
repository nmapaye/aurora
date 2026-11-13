// RESEARCH / UNVALIDATED. Debug builds only (both research defines come from
// Package.swift for Debug). Feeds the Debug-only Research screen; never shown
// to normal users and never used by any estimate, card or copy.
#if AURORA_RESEARCH_KSS && AURORA_RESEARCH_CAFFEINE
import Foundation

/// Both research models evaluated for the same moment from the same records,
/// so they can be read side by side. Nothing here is a person's alertness:
/// the KSS formula predicts a group-level sleepiness rating and the UMP a
/// group-average PVT lapse count, and both are unvalidated for individuals.
///
/// Shared schedule: recorded sleep in the `windowHours` before `at`, from the
/// first recorded sleep start, through `KSSModel.segments`. Time between
/// recorded sleeps counts as awake only when the caller confirms the record
/// is complete; otherwise both models refuse rather than impute a night.
/// The UMP's t = 0 is that first sleep start (the papers give no clock origin
/// for t, FLAGGED F1).
public struct ResearchComparison: Equatable, Sendable {
    public static let windowHours: Double = 72

    public struct KSS: Equatable, Sendable {
        /// Recorded caffeine passed in: the model refuses any positive dose.
        public var withRecordedCaffeine: KSSModel.Result
        /// Caffeine left out on purpose, labeled as such on screen.
        public var caffeineExcluded: KSSModel.Result
    }

    public enum UMPOutcome: Equatable, Sendable {
        case sample(UMPCaffeineModel.Sample)
        case refused(String)
    }

    public struct UMP: Equatable, Sendable {
        /// Recorded caffeine: at most one dose, modeled with the capsule
        /// absorption rate (no published rate for drinks, FLAGGED F3).
        public var withRecordedCaffeine: UMPOutcome
        public var caffeineFree: UMPOutcome
        public var dosesInWindow: Int
    }

    public var at: Millis
    public var segments: [KSSModel.Segment]
    public var kss: KSS
    public var ump: UMP

    public static func evaluate(at: Millis, sleeps: [SleepSession], doses: [Dose], timeZone: TimeZone,
                                unrecordedTimeIsConfirmedAwake: Bool) -> ResearchComparison {
        let windowStart = at - windowHours * hourMs
        let recent = sleeps.filter { $0.end > windowStart && $0.start < at }
            .map { session -> SleepSession in var clipped = session; clipped.start = max(session.start, windowStart); return clipped }
        let segments = KSSModel.segments(fromSleep: recent, until: at, unrecordedTimeIsConfirmedAwake: unrecordedTimeIsConfirmedAwake)
        let start = segments.first?.start ?? at
        let taken = doses.filter { $0.timestamp >= start && $0.timestamp <= at && $0.mg > 0 }
            .sorted { $0.timestamp < $1.timestamp }

        let recorded = KSSModel.CaffeineHistory(complete: true, doses: taken.map { .init(at: $0.timestamp, mg: $0.mg) })
        let kss = KSS(
            withRecordedCaffeine: KSSModel.predict(.init(at: at, timeZone: timeZone, history: segments, caffeine: recorded)),
            caffeineExcluded: KSSModel.predict(.init(at: at, timeZone: timeZone, history: segments, caffeine: .init(complete: true, doses: [])))
        )

        let ump = UMP(
            withRecordedCaffeine: umpOutcome(segments: segments, at: at, doses: taken),
            caffeineFree: umpOutcome(segments: segments, at: at, doses: []),
            dosesInWindow: taken.count
        )
        return ResearchComparison(at: at, segments: segments, kss: kss, ump: ump)
    }

    static func umpOutcome(segments: [KSSModel.Segment], at: Millis, doses: [Dose]) -> UMPOutcome {
        guard let start = segments.first?.start else { return .refused("No recorded sleep in the last \(Int(windowHours)) hours.") }
        var schedule: [UMPCaffeineModel.Episode] = []
        for segment in segments {
            switch segment.state {
            case .unknown: return .refused("Unrecorded time between sleeps; confirm the record is complete to treat it as awake.")
            case .sleep, .awake:
                let hours = (segment.end - segment.start) / hourMs
                guard hours > 0 else { continue }
                schedule.append(.init(segment.state == .sleep ? .asleep : .awake, hours: hours))
            }
        }
        let t = (at - start) / hourMs
        let modelDoses = doses.map { UMPCaffeineModel.Dose(atHours: ($0.timestamp - start) / hourMs, grams: $0.mg / 1000, formulation: .capsule) }
        do {
            guard let sample = try UMPCaffeineModel.simulate(schedule: schedule, dose: modelDoses, at: [t]).first else {
                return .refused("No sample.")
            }
            return .sample(sample)
        } catch let refusal as UMPCaffeineModel.Refusal {
            return .refused(describe(refusal))
        } catch {
            return .refused("\(error)")
        }
    }

    static func describe(_ refusal: UMPCaffeineModel.Refusal) -> String {
        switch refusal {
        case .repeatedDosesNotPublished: "More than one dose: repeated doses aren't published for this form (F2)."
        case .invalidEpisode(let index): "Episode \(index) has no length."
        case .timeOutsideSchedule(let t): "Time \(t) h is outside the schedule."
        case .invalidDose: "Dose outside the schedule or invalid."
        case .degenerateTimeConstants: "Degenerate time constants."
        }
    }
}
#endif
