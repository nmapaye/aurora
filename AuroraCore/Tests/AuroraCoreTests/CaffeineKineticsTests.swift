import Foundation
import Testing
@testable import AuroraCore

/// Golden cases and properties from `docs/research/caffeine.md` §6.4.
@Suite struct CaffeineKineticsTests {
    let pk = CaffeinePK(halfLifeHours: 5)
    /// 08:00 on Oct 10 2026 in the zone under test.
    func eight(_ zone: TimeZone) -> Millis {
        guard case .exact(let ms) = CutoffScenario.resolve(.init(year: 2026, month: 10, day: 10, hour: 8, minute: 0), in: zone) else { return .nan }
        return ms
    }

    static let zones = [TimeZone(identifier: "UTC")!, TimeZone(identifier: "America/Los_Angeles")!, .current]

    @Test(arguments: zones) func goldenSingleDose(zone: TimeZone) {
        let dose = [Dose(id: "a", timestamp: eight(zone), mg: 95)]
        // (τ hours, body A, uncleared N), ±0.01 mg.
        let rows: [(Double, Double, Double)] = [
            (0, 0.00, 95.00), (0.25, 58.86, 93.80), (0.5, 78.50, 91.36), (0.8707, 84.20, 87.12),
            (1, 83.87, 85.61), (2, 74.55, 74.58), (5, 49.21, 49.21), (8, 32.46, 32.46), (15, 12.30, 12.30),
        ]
        for (τ, body, uncleared) in rows {
            let t = eight(zone) + τ * hourMs
            #expect(abs(CaffeineKinetics.bodyMg(at: t, doses: dose, pk: pk) - body) <= 0.01, "A at τ=\(τ)")
            #expect(abs(CaffeineKinetics.unclearedMg(at: t, doses: dose, pk: pk) - uncleared) <= 0.01, "N at τ=\(τ)")
        }
        // The current instant model at the same times, for comparison.
        #expect(abs(Caffeine.activeMg(at: eight(zone) + hourMs, doses: dose, halfLifeHours: 5) - 82.70) <= 0.01)
        #expect(abs(Caffeine.activeMg(at: eight(zone) + 15 * hourMs, doses: dose, halfLifeHours: 5) - 11.88) <= 0.01)
    }

    @Test func peakDelayByHalfLife() {
        let minutes: [(Double, Double)] = [(2.5, 43.0), (4, 49.2), (5, 52.2), (6, 54.7), (8, 58.8), (10, 61.9)]
        for (halfLife, expected) in minutes {
            #expect(abs(CaffeineKinetics.peakDelayHours(pk: .init(halfLifeHours: halfLife)) * 60 - expected) < 0.05, "t½ \(halfLife)")
        }
        // The peak is the body curve's maximum.
        let peak = CaffeineKinetics.peakDelayHours(pk: pk)
        #expect(abs(peak - 0.8707) < 1e-4)
        let atPeak = CaffeineKinetics.bodyFraction(hours: peak, pk: pk)
        #expect(atPeak > CaffeineKinetics.bodyFraction(hours: peak - 0.01, pk: pk))
        #expect(atPeak > CaffeineKinetics.bodyFraction(hours: peak + 0.01, pk: pk))
    }

    @Test(arguments: [1.5, 2.5, 5, 9.9, 24]) func properties(halfLife: Double) {
        let pk = CaffeinePK(halfLifeHours: halfLife)
        var previous = Double.infinity
        var integral = 0.0
        let step = 0.001
        for i in 0...200_000 {
            let τ = Double(i) * step
            let a = CaffeineKinetics.bodyFraction(hours: τ, pk: pk)
            let n = CaffeineKinetics.unclearedFraction(hours: τ, pk: pk)
            if i % 100 == 0 {
                #expect(n <= previous, "N non-increasing at τ=\(τ)")
                #expect(a <= n + 1e-12, "A ≤ N at τ=\(τ)")
                previous = n
            }
            // Trapezoid ∫ ke·A dτ.
            integral += (i == 0 || i == 200_000 ? 0.5 : 1) * pk.eliminationPerHour * a * step
        }
        #expect(CaffeineKinetics.unclearedFraction(hours: 0, pk: pk) == 1)
        #expect(CaffeineKinetics.bodyFraction(hours: 0, pk: pk) == 0)
        #expect(CaffeineKinetics.bodyFraction(hours: 10_000, pk: pk) < 1e-12)
        // Mass is conserved: everything absorbed is eventually eliminated
        // (200 h is past 99.9 % for every half-life tested).
        let tail = CaffeineKinetics.unclearedFraction(hours: 200, pk: pk)
        #expect(abs(integral + tail - 1) < 1e-4, "∫ke·A = \(integral), tail \(tail)")
    }

    @Test func equalRatesUseTheLimit() {
        // ke = ka = 4 h⁻¹ when t½ = ln 2 / 4.
        let pk = CaffeinePK(halfLifeHours: log(2) / 4)
        let near = CaffeinePK(halfLifeHours: log(2) / 4.000001)
        for τ in [0.1, 0.5, 1, 3] {
            #expect(approxEqual(CaffeineKinetics.bodyFraction(hours: τ, pk: pk), CaffeineKinetics.bodyFraction(hours: τ, pk: near), tolerance: 1e-5))
            #expect(approxEqual(CaffeineKinetics.unclearedFraction(hours: τ, pk: pk), CaffeineKinetics.unclearedFraction(hours: τ, pk: near), tolerance: 1e-5))
        }
        #expect(approxEqual(CaffeineKinetics.peakDelayHours(pk: pk), 0.25, tolerance: 1e-6))
    }

    @Test func dosesSuperposeAndLaterDosesDontCount() {
        let t0: Millis = 1_790_000_000_000
        let a = Dose(id: "a", timestamp: t0, mg: 95)
        let b = Dose(id: "b", timestamp: t0 + 2 * hourMs, mg: 63)
        let later = Dose(id: "c", timestamp: t0 + 10 * hourMs, mg: 200)
        let t = t0 + 3 * hourMs
        #expect(approxEqual(
            CaffeineKinetics.bodyMg(at: t, doses: [a, b, later], pk: pk),
            CaffeineKinetics.bodyMg(at: t, doses: [a], pk: pk) + CaffeineKinetics.bodyMg(at: t, doses: [b], pk: pk)
        ))
        #expect(approxEqual(
            CaffeineKinetics.unclearedMg(at: t, doses: [a, b, later], pk: pk),
            CaffeineKinetics.unclearedMg(at: t, doses: [a], pk: pk) + CaffeineKinetics.unclearedMg(at: t, doses: [b], pk: pk)
        ))
        #expect(CaffeineKinetics.bodyMg(at: t, doses: [later], pk: pk) == 0)
        #expect(CaffeineKinetics.unclearedMg(at: t, doses: [later], pk: pk) == 0)
        #expect(approxEqual(CaffeineKinetics.plasmaMgPerL(at: t, doses: [a], pk: pk, volumeL: 42), CaffeineKinetics.bodyMg(at: t, doses: [a], pk: pk) / 42))
        #expect(CaffeineKinetics.plasmaMgPerL(at: t, doses: [a], pk: pk, volumeL: 0).isNaN)
    }

    @Test func risingUntilThePeak() {
        let t0: Millis = 1_790_000_000_000
        let dose = [Dose(id: "a", timestamp: t0, mg: 95)]
        #expect(CaffeineKinetics.isRising(at: t0, doses: dose, pk: pk))
        #expect(CaffeineKinetics.isRising(at: t0 + 0.85 * hourMs, doses: dose, pk: pk))
        #expect(!CaffeineKinetics.isRising(at: t0 + 0.9 * hourMs, doses: dose, pk: pk))
        #expect(!CaffeineKinetics.isRising(at: t0 - hourMs, doses: dose, pk: pk))
    }

    @Test func dstChangeCountsRealHours() {
        // 00:30 PDT to 03:30 PST on Nov 1 2026 is four hours, not three.
        let la = TimeZone(identifier: "America/Los_Angeles")!
        guard case .exact(let drink) = CutoffScenario.resolve(.init(year: 2026, month: 11, day: 1, hour: 0, minute: 30), in: la),
              case .exact(let later) = CutoffScenario.resolve(.init(year: 2026, month: 11, day: 1, hour: 3, minute: 30), in: la) else {
            Issue.record("expected exact times"); return
        }
        let dose = [Dose(id: "a", timestamp: drink, mg: 95)]
        #expect(CaffeineKinetics.bodyMg(at: later, doses: dose, pk: pk) == 95 * CaffeineKinetics.bodyFraction(hours: 4, pk: pk))
        #expect(CaffeineKinetics.unclearedMg(at: later, doses: dose, pk: pk) == 95 * CaffeineKinetics.unclearedFraction(hours: 4, pk: pk))
    }

    @Test(arguments: [0, -1, Double.nan, Double.infinity]) func invalidHalfLifeModelsNothing(value: Double) {
        let pk = CaffeinePK(halfLifeHours: value)
        #expect(!pk.isValid)
        #expect(CaffeineKinetics.bodyFraction(hours: 1, pk: pk) == 0)
        #expect(CaffeineKinetics.unclearedFraction(hours: 1, pk: pk) == 0)
        #expect(CaffeineKinetics.peakDelayHours(pk: pk) == 0)
    }

    @Test func parametersAreTheReportedConstants() throws {
        #expect(pk.absorptionPerHour == 4 && pk.bioavailability == 1)
        #expect(CaffeinePK.version == "caffeine-pk-2")
        #expect(try JSONDecoder().decode(CaffeinePK.self, from: JSONEncoder().encode(pk)) == pk)
    }
}
