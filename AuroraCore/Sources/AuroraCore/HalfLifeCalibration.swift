import Foundation

/// Deterministic 1-parameter half-life calibration over paired post-caffeine
/// KSS check-ins and Reaction Test scores (read-only proposal only; never
/// updates `Prefs.halfLife` without explicit user confirmation).
public enum HalfLifeCalibration {
    public static let windowDays = 30
    public static let minPairedObservations = 14
    public static let caffeineLookbackMs: Millis = 18 * hourMs
    public static let minShiftHours: Double = 1.0
    public static let minRelativeImprovement: Double = 0.10
    public static let candidateHalfLives: [Double] = stride(from: 3.0, through: 8.0, by: 0.5).map { $0 }

    public struct Proposal: Equatable, Sendable {
        public var currentHalfLifeHours: Double
        public var proposedHalfLifeHours: Double
        public var pairedObservations: Int
        public var checkInCount: Int
        public var reactionTestCount: Int
        public var currentError: Double
        public var proposedError: Double
        public var reason: String

        public init(
            currentHalfLifeHours: Double,
            proposedHalfLifeHours: Double,
            pairedObservations: Int,
            checkInCount: Int,
            reactionTestCount: Int,
            currentError: Double,
            proposedError: Double,
            reason: String
        ) {
            self.currentHalfLifeHours = currentHalfLifeHours
            self.proposedHalfLifeHours = proposedHalfLifeHours
            self.pairedObservations = pairedObservations
            self.checkInCount = checkInCount
            self.reactionTestCount = reactionTestCount
            self.currentError = currentError
            self.proposedError = proposedError
            self.reason = reason
        }
    }

    public enum Status: Equatable, Sendable {
        case insufficientData(pairedCount: Int, needed: Int)
        case aligned(currentHalfLifeHours: Double, pairedCount: Int)
        case proposed(Proposal)
    }

    private struct Observation {
        var t: Millis
        var score: Double
        var isCheckIn: Bool
        var troughHour: Double?
    }

    public static func evaluate(state: AppState, now: Millis, clock: LocalClock) -> Status {
        let currentHalfLife = (state.prefs.halfLife.isFinite && state.prefs.halfLife > 0)
            ? state.prefs.halfLife
            : Prefs.defaultHalfLife
        let targetSleep = (state.prefs.targetSleep.isFinite && state.prefs.targetSleep > 0)
            ? state.prefs.targetSleep
            : Prefs.defaultTargetSleep
        let effectiveClock = state.prefs.tz.flatMap(TimeZone.init(identifier:)).map(LocalClock.init(timeZone:)) ?? clock
        let useCircadian = state.prefs.usesPersonalCircadianPhase
        let useRamp = state.prefs.usesGradualCaffeineOnset

        let realDoses = state.doses.filter {
            !RecordID.isSample($0.id) && $0.timestamp.isFinite && $0.timestamp <= now && $0.mg.isFinite && $0.mg > 0
        }
        let realSleeps = state.sleeps.filter {
            !RecordID.isSample($0.id) && $0.start.isFinite && $0.end.isFinite && $0.end > $0.start && $0.start <= now
        }

        let windowStart = now - Double(windowDays) * dayMs
        var candidates: [(t: Millis, score: Double, isCheckIn: Bool)] = []
        for checkIn in state.energyCheckIns {
            guard !RecordID.isSample(checkIn.id),
                  checkIn.recordedScale == .kss,
                  (1...9).contains(checkIn.rating),
                  checkIn.recordedAt.isFinite,
                  checkIn.recordedAt >= windowStart,
                  checkIn.recordedAt <= now else { continue }
            let mapped = Double(9 - checkIn.rating) / 8.0 * 100.0
            candidates.append((checkIn.recordedAt, mapped, true))
        }
        for session in state.vigilanceSessions {
            guard !RecordID.isSample(session.id),
                  session.protocolVersion == 2,
                  (0...100).contains(session.score),
                  session.completedAt.isFinite,
                  session.completedAt >= windowStart,
                  session.completedAt <= now else { continue }
            candidates.append((session.completedAt, Double(session.score), false))
        }

        let baseInputs = EstimateInputs(
            halfLifeHours: currentHalfLife,
            targetSleepHours: targetSleep,
            clock: effectiveClock,
            usePersonalCircadianPhase: useCircadian,
            useAbsorptionRamp: useRamp
        )

        var paired: [Observation] = []
        var checkInCount = 0
        var reactionTestCount = 0
        for item in candidates {
            let hasRecentDose = realDoses.contains {
                item.t - caffeineLookbackMs <= $0.timestamp && $0.timestamp <= item.t
            }
            guard hasRecentDose,
                  Summary.estimateAlertness(at: item.t, doses: realDoses, sleeps: realSleeps, inputs: baseInputs).score != nil else {
                continue
            }
            let trough: Double?
            if useCircadian {
                let anchor = Circadian.anchor(sleeps: realSleeps, at: item.t, clock: effectiveClock)
                trough = anchor.source == .defaultFixed ? nil : anchor.troughHour
            } else {
                trough = nil
            }
            paired.append(Observation(t: item.t, score: item.score, isCheckIn: item.isCheckIn, troughHour: trough))
            if item.isCheckIn {
                checkInCount += 1
            } else {
                reactionTestCount += 1
            }
        }

        guard paired.count >= minPairedObservations else {
            return .insufficientData(pairedCount: paired.count, needed: minPairedObservations)
        }

        func centeredRMSE(halfLife: Double) -> Double {
            var residuals: [Double] = []
            residuals.reserveCapacity(paired.count)
            for obs in paired {
                let predicted = Alertness.score(
                    at: obs.t,
                    doses: realDoses,
                    sleeps: realSleeps,
                    halfLifeHours: halfLife,
                    targetSleepHours: targetSleep,
                    clock: effectiveClock,
                    circadianTroughHour: obs.troughHour,
                    useAbsorptionRamp: useRamp
                )
                residuals.append(obs.score - predicted)
            }
            let count = Double(residuals.count)
            let meanResidual = residuals.reduce(0, +) / count
            let variance = residuals.reduce(0) { total, r in
                let centered = r - meanResidual
                return total + centered * centered
            } / count
            return sqrt(variance)
        }

        let currentErr = centeredRMSE(halfLife: currentHalfLife)
        var bestHalfLife = currentHalfLife
        var bestErr = currentErr
        for candidate in candidateHalfLives {
            let err = centeredRMSE(halfLife: candidate)
            if err + 1e-9 < bestErr {
                bestErr = err
                bestHalfLife = candidate
            } else if abs(err - bestErr) <= 1e-9 && abs(candidate - currentHalfLife) < abs(bestHalfLife - currentHalfLife) {
                bestHalfLife = candidate
            }
        }

        guard currentErr > 1e-6,
              abs(bestHalfLife - currentHalfLife) >= minShiftHours,
              (currentErr - bestErr) / currentErr >= minRelativeImprovement else {
            return .aligned(currentHalfLifeHours: currentHalfLife, pairedCount: paired.count)
        }

        let reason = "Based on \(paired.count) logs after caffeine in the last \(windowDays) days, a \(numberText(bestHalfLife))h half-life matches your recorded sleepiness and reaction timing more closely than \(numberText(currentHalfLife))h. Modeled estimate only; tap to update your setting."

        return .proposed(Proposal(
            currentHalfLifeHours: currentHalfLife,
            proposedHalfLifeHours: bestHalfLife,
            pairedObservations: paired.count,
            checkInCount: checkInCount,
            reactionTestCount: reactionTestCount,
            currentError: currentErr,
            proposedError: bestErr,
            reason: reason
        ))
    }
}
