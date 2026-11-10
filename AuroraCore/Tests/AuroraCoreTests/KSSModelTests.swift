#if AURORA_RESEARCH_KSS
import Foundation
import Testing
@testable import AuroraCore

/// Research-only TPM → KSS formula. Reference values are synthetic
/// mathematical cases (not human KSS observations):
/// - kss-tpm-ts-reference.json: outputs of website/research/tpm-kss.ts on
///   identical inputs (Tools/kss-tpm-reference/generate.mjs).
/// - kss-tpm-rk4-reference.json: independent Python RK4 integration of the
///   same differential dynamics (website/research/make-reference-fixtures.py).
struct KSSModelTests {
    struct RefInput: Decodable {
        var at: Double
        var timeZone: String
        var phaseHours: Double
        var history: [KSSModel.Segment]
        var caffeine: KSSModel.CaffeineHistory?
    }
    struct RefExpected: Decodable {
        var status: String?
        var reason: String?
        var rawKss: Double?
        var boundedKss: Double?
        var hoursAwake: Double?
        var homeostatic: Double?
        var circadian: Double?
        var ultradian: Double?
        var inertia: Double?
    }
    struct RefCase: Decodable { var name: String; var input: RefInput; var expected: RefExpected }
    struct RefFile: Decodable { var tsSha256: String?; var cases: [RefCase] }

    static func load(_ name: String) throws -> RefFile {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(RefFile.self, from: Data(contentsOf: url))
    }

    static func input(_ r: RefInput) -> KSSModel.Input {
        KSSModel.Input(at: r.at, timeZone: TimeZone(identifier: r.timeZone), phaseHours: r.phaseHours, history: r.history, caffeine: r.caffeine)
    }

    static let H: Millis = hourMs
    static let base: Millis = 1_792_537_200_000 // Oct 20 2026 23:00 UTC
    static let utc = TimeZone(identifier: "UTC")!

    func timeline(_ plan: [(KSSModel.SegmentState, Double)], start: Millis = Self.base) -> (history: [KSSModel.Segment], at: Millis) {
        var t = start
        var out: [KSSModel.Segment] = []
        for (state, hours) in plan where hours > 0 {
            out.append(.init(state: state, start: t, end: t + hours * Self.H)); t += hours * Self.H
        }
        return (out, t)
    }

    // MARK: Cross-check Swift vs TypeScript (identical inputs)

    @Test func matchesTypeScriptReferenceForEveryCase() throws {
        let file = try Self.load("kss-tpm-ts-reference")
        #expect(file.cases.count == 41)
        #expect(file.tsSha256 == "24bc58e37dacdeb0a08c019a3032c6073673e8f995314f6f23d19842be6bfb25")
        var predicted = 0, refused = 0
        for c in file.cases {
            let result = KSSModel.predict(Self.input(c.input))
            if c.expected.status == "research-baseline-only" {
                let p = try #require(result.prediction, "\(c.name): expected prediction, got \(String(describing: result.refusal))")
                let tol = 1e-9
                #expect(abs(p.rawKSS - c.expected.rawKss!) <= tol, "\(c.name) rawKSS \(p.rawKSS) vs \(c.expected.rawKss!)")
                #expect(abs(p.boundedKSS - c.expected.boundedKss!) <= tol, "\(c.name)")
                #expect(abs(p.hoursAwake - c.expected.hoursAwake!) <= tol, "\(c.name)")
                #expect(abs(p.components.homeostatic - c.expected.homeostatic!) <= tol, "\(c.name) S")
                #expect(abs(p.components.circadian - c.expected.circadian!) <= tol, "\(c.name) C")
                #expect(abs(p.components.ultradian - c.expected.ultradian!) <= tol, "\(c.name) U")
                #expect(abs(p.components.inertia - c.expected.inertia!) <= tol, "\(c.name) W")
                predicted += 1
            } else {
                #expect(result.refusal?.rawValue == c.expected.reason, "\(c.name)")
                refused += 1
            }
        }
        #expect(predicted == 28)
        #expect(refused == 13)
    }

    // MARK: Independent numerical reference (Python RK4 of the ODEs)

    @Test func matchesIndependentRK4Integration() throws {
        let file = try Self.load("kss-tpm-rk4-reference")
        #expect(file.cases.count == 16)
        for c in file.cases {
            let p = try #require(KSSModel.predict(Self.input(c.input)).prediction, "\(c.name)")
            let tol = 3e-7 // RK4 step 0.001 h, as in website/research/validation-results.json
            #expect(abs(p.rawKSS - c.expected.rawKss!) <= tol, "\(c.name)")
            #expect(abs(p.components.homeostatic - c.expected.homeostatic!) <= tol, "\(c.name)")
            #expect(abs(p.components.circadian - c.expected.circadian!) <= tol, "\(c.name)")
            #expect(abs(p.components.ultradian - c.expected.ultradian!) <= tol, "\(c.name)")
            #expect(abs(p.components.inertia - c.expected.inertia!) <= tol, "\(c.name)")
        }
    }

    // MARK: Published constants and equation properties

    @Test func publishedConstantsAreTheOriginalFullModel() {
        let p = KSSModel.Parameters.original
        #expect(p.upperAsymptote == 14.3 && p.lowerAsymptote == 2.4)
        #expect(p.wakeDecayRate == -0.0353 && p.brakeLevel == 12.2)
        #expect(p.inertiaAmplitude == -5.72 && p.inertiaRecoveryRate == -1.51)
        #expect(p.circadianAmplitude == 2.5 && p.circadianMesor == 0)
        #expect(p.ultradianAmplitude == 0.5 && p.ultradianMesor == -0.5 && p.ultradianPhaseOffsetHours == 3)
        #expect(p.defaultPhaseHours == 16.8)
        #expect(p.kssIntercept == 10.6 && p.kssSlope == -0.6)
        #expect(p.sleepEntryThreshold == 8.38)
        // Ingre 2014 states g = log((ha − 14.0)/(ha − 7.96))/8 ≈ −0.3813 (printed to 4 dp; exact −0.381356…).
        #expect(abs(p.sleepRecoveryRate - (-0.3813)) < 1e-4)
        // The published recovery calibration: from 7.96, 8 h of eq 1.2 reaches 14.0.
        #expect(abs(KSSModel.originalSleepState(7.96, hours: 8) - 14.0) < 1e-12)
    }

    @Test func brakeIsContinuousAndRecoveryIsMonotonic() {
        let p = KSSModel.Parameters.original
        let rate = p.sleepRecoveryRate * (p.brakeLevel - p.upperAsymptote)
        let start = 6.0
        let bt = (p.brakeLevel - start) / rate
        #expect(abs(KSSModel.sleepState(start, hours: bt) - p.brakeLevel) < 1e-12)
        #expect(abs(KSSModel.sleepState(start, hours: bt + 1e-9) - p.brakeLevel) < 1e-8)
        var last = start
        for h in stride(from: 0.25, through: 24, by: 0.25) {
            let s = KSSModel.sleepState(start, hours: h)
            #expect(s >= last && s < p.upperAsymptote)
            last = s
        }
        #expect(KSSModel.wakeState(14, hours: 1000) > p.lowerAsymptote)
        #expect(abs(KSSModel.inertia(hoursAwake: 0) - p.inertiaAmplitude) < 1e-12)
    }

    @Test func boundedKSSStaysOnTheNinePointScale() throws {
        // Waking from 2 h sleep after 36 h awake at the circadian trough.
        let t = timeline([(.sleep, 8), (.awake, 36), (.sleep, 2)])
        let p = try #require(KSSModel.predict(.init(at: t.at, timeZone: Self.utc, history: t.history, caffeine: .init(complete: true, doses: []))).prediction)
        #expect(p.boundedKSS >= 1 && p.boundedKSS <= 9)
        #expect(p.boundedKSS == min(9, max(1, p.rawKSS)))
    }

    // MARK: Edge cases

    @Test func noSleepDataIsRefusedNotZero() {
        let result = KSSModel.predict(.init(at: Self.base, timeZone: Self.utc, history: [], caffeine: .init(complete: true, doses: [])))
        #expect(result == .notSupported(.missingSleepHistory))
        let fromRecords = KSSModel.segments(fromSleep: [], until: Self.base, unrecordedTimeIsConfirmedAwake: true)
        #expect(fromRecords.isEmpty)
    }

    @Test func invalidTimeZoneIsRefused() {
        let t = timeline([(.sleep, 8), (.awake, 16), (.sleep, 8), (.awake, 2)])
        #expect(KSSModel.predict(.init(at: t.at, timeZone: nil, history: t.history, caffeine: .init(complete: true, doses: []))) == .notSupported(.invalidTimeZone))
    }

    @Test func fragmentedSleepIsModeledFragmentByFragment() throws {
        let caffeine = KSSModel.CaffeineHistory(complete: true, doses: [])
        let solid = timeline([(.sleep, 8), (.awake, 16), (.sleep, 7), (.awake, 2)])
        let broken = timeline([(.sleep, 8), (.awake, 16), (.sleep, 3), (.awake, 1), (.sleep, 3), (.awake, 2)])
        let a = try #require(KSSModel.predict(.init(at: solid.at, timeZone: Self.utc, history: solid.history, caffeine: caffeine)).prediction)
        let b = try #require(KSSModel.predict(.init(at: broken.at, timeZone: Self.utc, history: broken.history, caffeine: caffeine)).prediction)
        // Same 6 h asleep minus 1 h awake mid-night: less homeostatic recovery than 7 h solid.
        #expect(b.components.homeostatic < a.components.homeostatic)
        #expect(b.hoursAwake == 2)
    }

    @Test func adapterMergesOverlapsAndKeepsAwakenings() throws {
        let s = Self.base
        let sleeps = [
            SleepSession(id: "a", start: s, end: s + 8 * Self.H),
            SleepSession(id: "b", start: s + 24 * Self.H, end: s + 27 * Self.H),
            SleepSession(id: "c", start: s + 26 * Self.H, end: s + 27.5 * Self.H), // overlaps b
            SleepSession(id: "d", start: s + 28 * Self.H, end: s + 31 * Self.H, type: .nap), // 30 min awakening
        ]
        let at = s + 33 * Self.H
        let segs = KSSModel.segments(fromSleep: sleeps, until: at, unrecordedTimeIsConfirmedAwake: true)
        #expect(segs.map(\.state) == [.sleep, .awake, .sleep, .awake, .sleep, .awake])
        #expect(segs[2].end == s + 27.5 * Self.H)
        #expect(segs[3].end - segs[3].start == 0.5 * Self.H)
        #expect(segs.last?.end == at)
        let p = try #require(KSSModel.predict(.init(at: at, timeZone: Self.utc, history: segs, caffeine: .init(complete: true, doses: []))).prediction)
        #expect(p.hoursAwake == 2)
    }

    @Test func unconfirmedGapsBetweenRecordsAreNeverAssumedAwake() {
        let s = Self.base
        let sleeps = [SleepSession(id: "a", start: s, end: s + 8 * Self.H), SleepSession(id: "b", start: s + 24 * Self.H, end: s + 32 * Self.H)]
        let segs = KSSModel.segments(fromSleep: sleeps, until: s + 34 * Self.H, unrecordedTimeIsConfirmedAwake: false)
        #expect(segs.contains { $0.state == .unknown })
        #expect(KSSModel.predict(.init(at: s + 34 * Self.H, timeZone: Self.utc, history: segs, caffeine: .init(complete: true, doses: []))) == .notSupported(.unknownSleepWakeState))
    }

    @Test func caffeineIsNeverFedIntoTheFormula() {
        let t = timeline([(.sleep, 8), (.awake, 16), (.sleep, 8), (.awake, 3)])
        let dose = KSSModel.TimedCaffeine(at: t.at - Self.H, mg: 95)
        #expect(KSSModel.predict(.init(at: t.at, timeZone: Self.utc, history: t.history, caffeine: .init(complete: true, doses: [dose]))) == .notSupported(.caffeineEffectNotValidated))
        #expect(KSSModel.predict(.init(at: t.at, timeZone: Self.utc, history: t.history, caffeine: nil)) == .notSupported(.unknownCaffeineHistory))
    }

    // MARK: Gate

    @Test func labeledResearchUnvalidated() throws {
        #expect(KSSModel.version.contains("research-unvalidated"))
        let t = timeline([(.sleep, 8), (.awake, 16), (.sleep, 8), (.awake, 3)])
        let p = try #require(KSSModel.predict(.init(at: t.at, timeZone: Self.utc, history: t.history, caffeine: .init(complete: true, doses: []))).prediction)
        #expect(p.validation.contains("Research only"))
        #expect(p.caffeine.hasPrefix("Not modeled"))
    }

    @Test func appSourcesNeverReferenceTheResearchModel() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = repo.appendingPathComponent("Aurora")
        guard FileManager.default.fileExists(atPath: app.path) else { return }
        let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty)
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8)
            #expect(!text.contains("KSSModel"), "\(f.lastPathComponent) references the research KSS model")
            #expect(!text.contains("AURORA_RESEARCH_KSS"), "\(f.lastPathComponent)")
        }
    }
}
#endif
