#if AURORA_RESEARCH_KSS && AURORA_RESEARCH_CAFFEINE
import Foundation
import Testing
@testable import AuroraCore

/// The Debug Research screen's side-by-side inputs: both models read the
/// same recorded schedule and agree with calling each model directly.
struct ResearchComparisonTests {
    static let utc = TimeZone(identifier: "UTC")!
    /// Thu, Oct 8, 2026, 00:00 UTC.
    static let base: Millis = 1_791_417_600_000

    func night(_ id: String, day: Double, from: Double, hours: Double) -> SleepSession {
        let start = Self.base + (day * 24 + from) * hourMs
        return SleepSession(id: id, start: start, end: start + hours * hourMs)
    }
    /// Two recorded nights, then 14:00 on the third day.
    var twoNights: (sleeps: [SleepSession], at: Millis) {
        ([night("a", day: 0, from: 23, hours: 8), night("b", day: 1, from: 23, hours: 8)], Self.base + (2 * 24 + 14) * hourMs)
    }

    @Test func unconfirmedGapsRefuseInsteadOfImputingANight() {
        let (sleeps, at) = twoNights
        let c = ResearchComparison.evaluate(at: at, sleeps: sleeps, doses: [], timeZone: Self.utc, unrecordedTimeIsConfirmedAwake: false)
        #expect(c.kss.caffeineExcluded.refusal == .unknownSleepWakeState)
        guard case .refused = c.ump.caffeineFree else { Issue.record("UMP should refuse unknown time"); return }
    }

    @Test func noSleepRecordedRefusesBoth() {
        let at = Self.base + 14 * hourMs
        let c = ResearchComparison.evaluate(at: at, sleeps: [], doses: [], timeZone: Self.utc, unrecordedTimeIsConfirmedAwake: true)
        #expect(c.segments.isEmpty)
        #expect(c.kss.caffeineExcluded.prediction == nil)
        guard case .refused = c.ump.caffeineFree else { Issue.record("UMP should refuse with no sleep"); return }
    }

    @Test func confirmedScheduleMatchesEachModelCalledDirectly() throws {
        let (sleeps, at) = twoNights
        let c = ResearchComparison.evaluate(at: at, sleeps: sleeps, doses: [], timeZone: Self.utc, unrecordedTimeIsConfirmedAwake: true)
        let direct = KSSModel.predict(.init(at: at, timeZone: Self.utc,
                                            history: KSSModel.segments(fromSleep: sleeps, until: at, unrecordedTimeIsConfirmedAwake: true),
                                            caffeine: .init(complete: true, doses: [])))
        #expect(c.kss.caffeineExcluded == direct)
        #expect(c.kss.withRecordedCaffeine == direct)
        let kss = try #require(c.kss.caffeineExcluded.prediction)
        #expect((1...9).contains(kss.boundedKSS))
        // UMP: sleep 8 h, awake 16 h, sleep 8 h, awake 7 h, from the first sleep start.
        let schedule: [UMPCaffeineModel.Episode] = [.init(.asleep, hours: 8), .init(.awake, hours: 16), .init(.asleep, hours: 8), .init(.awake, hours: 7)]
        let expected = try #require(try UMPCaffeineModel.simulate(schedule: schedule, at: [39]).first)
        #expect(c.ump.caffeineFree == .sample(expected))
        #expect(c.ump.withRecordedCaffeine == .sample(expected))
        #expect(c.ump.dosesInWindow == 0)
    }

    @Test func oneDoseUsesCapsuleAbsorptionAndKSSRefusesCaffeine() throws {
        let (sleeps, at) = twoNights
        let dose = Dose(id: "d", timestamp: at - 3 * hourMs, mg: 200)
        let c = ResearchComparison.evaluate(at: at, sleeps: sleeps, doses: [dose], timeZone: Self.utc, unrecordedTimeIsConfirmedAwake: true)
        #expect(c.kss.withRecordedCaffeine.refusal == .caffeineEffectNotValidated)
        #expect(c.kss.caffeineExcluded.prediction != nil)
        let schedule: [UMPCaffeineModel.Episode] = [.init(.asleep, hours: 8), .init(.awake, hours: 16), .init(.asleep, hours: 8), .init(.awake, hours: 7)]
        let expected = try #require(try UMPCaffeineModel.simulate(schedule: schedule, dose: [.init(atHours: 36, grams: 0.2, formulation: .capsule)], at: [39]).first)
        #expect(c.ump.withRecordedCaffeine == .sample(expected))
        guard case .sample(let free) = c.ump.caffeineFree, case .sample(let with) = c.ump.withRecordedCaffeine else { Issue.record("expected samples"); return }
        #expect(with.caffeineFactor < 1 && free.caffeineFactor == 1)
    }

    @Test func twoDosesRefuseTheUMPNotTheCaffeineFreeRun() {
        let (sleeps, at) = twoNights
        let doses = [Dose(id: "d1", timestamp: at - 5 * hourMs, mg: 95), Dose(id: "d2", timestamp: at - 2 * hourMs, mg: 95)]
        let c = ResearchComparison.evaluate(at: at, sleeps: sleeps, doses: doses, timeZone: Self.utc, unrecordedTimeIsConfirmedAwake: true)
        #expect(c.ump.dosesInWindow == 2)
        guard case .refused(let why) = c.ump.withRecordedCaffeine else { Issue.record("expected F2 refusal"); return }
        #expect(why.contains("F2"))
        guard case .sample = c.ump.caffeineFree else { Issue.record("caffeine-free run should still sample"); return }
    }

    @Test func sleepOlderThanTheWindowIsIgnored() {
        let at = Self.base + (5 * 24 + 14) * hourMs
        let c = ResearchComparison.evaluate(at: at, sleeps: [night("old", day: 0, from: 23, hours: 8)], doses: [],
                                            timeZone: Self.utc, unrecordedTimeIsConfirmedAwake: true)
        #expect(c.segments.isEmpty)
    }

    /// App code may reference the research models only from the Debug-only
    /// Research screen, wrapped in `#if DEBUG`.
    @Test func onlyTheDebugResearchScreenReferencesTheModels() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = repo.appendingPathComponent("Aurora")
        guard FileManager.default.fileExists(atPath: app.path) else { return }
        let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        let allowed: Set<String> = ["ResearchModelsView.swift"]
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8)
            let refers = ["KSSModel", "UMPCaffeineModel", "ResearchComparison", "AURORA_RESEARCH"].contains { text.contains($0) }
            guard refers else { continue }
            #expect(allowed.contains(f.lastPathComponent), "\(f.lastPathComponent) references a research model")
            let firstCode = text.split(separator: "\n").first { !$0.hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            #expect(firstCode == "#if DEBUG", "\(f.lastPathComponent) must be wrapped in #if DEBUG")
        }
    }
}
#endif
