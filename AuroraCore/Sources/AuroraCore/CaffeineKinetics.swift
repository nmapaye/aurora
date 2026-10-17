import Foundation

/// Parameters of the modeled caffeine time course: a one-compartment oral
/// model with first-order absorption (the Bateman function, the same form
/// 2B-Alert uses), with plasma-like rates rather than alertness-fitted ones.
///
/// - `halfLifeHours`: the person's own Settings value; sets elimination.
/// - `absorptionPerHour` (ka): 4 h⁻¹, which puts the modeled peak about
///   52 minutes after a drink at a 5 h half-life (Liguori 1997; Blanchard &
///   Sawers 1983). A fixed constant, not a setting.
/// - `bioavailability` (F): 1, as oral caffeine is essentially completely
///   absorbed (Blanchard & Sawers 1983).
///
/// See `docs/research/caffeine.md` §4 and §6.1.
public struct CaffeinePK: Codable, Equatable, Sendable {
    public static let version = "caffeine-pk-2"
    public static let defaultAbsorptionPerHour: Double = 4.0
    public static let defaultBioavailability: Double = 1.0

    public var halfLifeHours: Double
    public var absorptionPerHour: Double
    public var bioavailability: Double

    public init(
        halfLifeHours: Double,
        absorptionPerHour: Double = CaffeinePK.defaultAbsorptionPerHour,
        bioavailability: Double = CaffeinePK.defaultBioavailability
    ) {
        self.halfLifeHours = halfLifeHours
        self.absorptionPerHour = absorptionPerHour
        self.bioavailability = bioavailability
    }

    /// ke = ln 2 / t½, per hour.
    public var eliminationPerHour: Double { log(2) / halfLifeHours }

    /// Every rate finite and above 0, and F finite and not negative. Callers
    /// check this first and show their own problem (as
    /// `CutoffScenario.halfLifeProblem` does); the functions below return 0
    /// for parameters that fail it rather than a meaningless number.
    public var isValid: Bool {
        halfLifeHours.isFinite && halfLifeHours > 0
            && absorptionPerHour.isFinite && absorptionPerHour > 0
            && bioavailability.isFinite && bioavailability >= 0
    }
}

/// Modeled caffeine over time, in mg, from logged doses. Pure functions on
/// absolute instants, so a daylight-saving change between a drink and a
/// later time counts real elapsed hours.
///
/// Two quantities:
/// - **In the body** `A(τ)`: absorbed and not yet eliminated. Starts at 0,
///   peaks after `peakDelayHours`, then falls. Drives the active-caffeine
///   display and the Today chart.
/// - **Not yet cleared** `N(τ)`: still being absorbed plus already in the
///   body. Starts at the full dose and only ever falls (`dN/dτ = −ke·A`), so
///   the cutoff scenario has one well-defined answer.
///
/// Interface for the alertness model: `bodyMg(at:doses:pk:)` is the amount a
/// plasma concentration is proportional to (`C = A/V`). A pharmacodynamic
/// model that brings its own kinetics (2B-Alert's `g_PD`) should take the
/// doses directly instead, or absorption and elimination are counted twice.
///
/// The current alertness score does not use this yet: it still takes
/// `Caffeine.activeEffect`, the instant-decay model ported from the React
/// Native build.
public enum CaffeineKinetics {
    /// Below this |ka − ke| the closed form divides by ~0; its limit is used.
    static let equalRatesTolerance = 1e-9

    /// Fraction of one dose absorbed and not yet eliminated, τ hours after
    /// intake; 0 for τ < 0.
    ///
    /// `F · ka/(ka − ke) · (e^(−ke·τ) − e^(−ka·τ))`
    public static func bodyFraction(hours τ: Double, pk: CaffeinePK) -> Double {
        guard pk.isValid, τ.isFinite, τ >= 0 else { return 0 }
        let ka = pk.absorptionPerHour, ke = pk.eliminationPerHour
        let value: Double
        if abs(ka - ke) < equalRatesTolerance {
            value = ka * τ * exp(-ke * τ)
        } else {
            value = ka / (ka - ke) * (exp(-ke * τ) - exp(-ka * τ))
        }
        return max(0, pk.bioavailability * value)
    }

    /// Fraction of one dose not yet cleared (still being absorbed plus in the
    /// body), τ hours after intake. F at τ = 0, then strictly decreasing; 0
    /// for τ < 0 (not taken yet).
    ///
    /// `F · (ka·e^(−ke·τ) − ke·e^(−ka·τ)) / (ka − ke)`
    public static func unclearedFraction(hours τ: Double, pk: CaffeinePK) -> Double {
        guard pk.isValid, τ.isFinite, τ >= 0 else { return 0 }
        let ka = pk.absorptionPerHour, ke = pk.eliminationPerHour
        let value: Double
        if abs(ka - ke) < equalRatesTolerance {
            value = (1 + ke * τ) * exp(-ke * τ)
        } else {
            value = (ka * exp(-ke * τ) - ke * exp(-ka * τ)) / (ka - ke)
        }
        return min(pk.bioavailability, max(0, pk.bioavailability * value))
    }

    /// Rate of change of `bodyFraction` per hour; positive while absorption
    /// outpaces elimination.
    static func bodyFractionSlope(hours τ: Double, pk: CaffeinePK) -> Double {
        guard pk.isValid, τ.isFinite, τ >= 0 else { return 0 }
        let ka = pk.absorptionPerHour, ke = pk.eliminationPerHour
        if abs(ka - ke) < equalRatesTolerance {
            return pk.bioavailability * ka * (1 - ke * τ) * exp(-ke * τ)
        }
        return pk.bioavailability * ka / (ka - ke) * (ka * exp(-ka * τ) - ke * exp(-ke * τ))
    }

    /// Hours from intake to the modeled peak of `bodyFraction`:
    /// `ln(ka/ke) / (ka − ke)`, or `1/k` when the rates are equal. 0 for
    /// invalid parameters.
    public static func peakDelayHours(pk: CaffeinePK) -> Double {
        guard pk.isValid else { return 0 }
        let ka = pk.absorptionPerHour, ke = pk.eliminationPerHour
        if abs(ka - ke) < equalRatesTolerance { return 1 / ka }
        return log(ka / ke) / (ka - ke)
    }

    /// Σ mg in the body at `t`. Doses after `t` contribute 0.
    public static func bodyMg(at t: Millis, doses: [Dose], pk: CaffeinePK) -> Double {
        doses.reduce(0) { total, dose in
            guard dose.timestamp <= t else { return total }
            return total + dose.mg * bodyFraction(hours: (t - dose.timestamp) / hourMs, pk: pk)
        }
    }

    /// Σ mg not yet cleared at `t` (still being absorbed plus in the body).
    /// Doses after `t` contribute 0.
    public static func unclearedMg(at t: Millis, doses: [Dose], pk: CaffeinePK) -> Double {
        doses.reduce(0) { total, dose in
            guard dose.timestamp <= t else { return total }
            return total + dose.mg * unclearedFraction(hours: (t - dose.timestamp) / hourMs, pk: pk)
        }
    }

    /// Whether the modeled body amount is rising at `t`: some dose is still
    /// being absorbed faster than the total is eliminated.
    public static func isRising(at t: Millis, doses: [Dose], pk: CaffeinePK) -> Bool {
        let slope = doses.reduce(0) { total, dose in
            guard dose.timestamp <= t else { return total }
            return total + dose.mg * bodyFractionSlope(hours: (t - dose.timestamp) / hourMs, pk: pk)
        }
        return slope > 0
    }

    /// mg/L for a distribution volume the caller supplies (about 0.6 L/kg of
    /// body weight). Aurora never asks for weight; this is only for a model
    /// that already has one. NaN for a volume that isn't above 0.
    public static func plasmaMgPerL(at t: Millis, doses: [Dose], pk: CaffeinePK, volumeL: Double) -> Double {
        guard volumeL.isFinite, volumeL > 0 else { return .nan }
        return bodyMg(at: t, doses: doses, pk: pk) / volumeL
    }
}
