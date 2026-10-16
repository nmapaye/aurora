import Foundation
import Testing
@testable import AuroraCore

/// iPhone-only Health data: time in bed, read and shown apart from sleep and
/// never counted as asleep (sleep-and-check-in §4 R2, §8 Q2 option A).
@MainActor
@Suite("Time in bed")
struct TimeInBedTests {
    typealias G = SleepGolden

    /// Health with only iPhone time in bed and, optionally, asleep samples.
    final class InBedHealth: HealthDataProvider, @unchecked Sendable {
        var inBed: [HealthSleepSample] = []
        var asleep: [HealthSleepSample] = []
        var failInBed = false
        var inBedReads = 0
        var capabilities: HealthCapabilities = [.readSleep, .readSleepChanges, .readInBed]
        var isAvailable: Bool { true }

        func sleepChanges(after anchor: Data?) async throws -> HealthSleepChanges {
            HealthSleepChanges(added: anchor == nil ? asleep : [], deletedSampleUUIDs: [], anchor: Data("1".utf8))
        }

        func inBedSamples(from start: Millis, to end: Millis) async throws -> [HealthSleepSample] {
            inBedReads += 1
            if failInBed { throw HealthProviderError.unavailable }
            return inBed.filter { $0.end > start && $0.start < end }
        }
    }

    static func sample(_ uuid: String, _ start: Millis, _ end: Millis) -> HealthSleepSample {
        HealthSleepSample(start: start, end: end, provenance: HealthSampleProvenance(sampleUUID: uuid, sourceBundleIdentifier: "com.apple.health", sourceName: "iPhone"))
    }

    let now = SleepGolden.at(0, 9)

    @Test func e6OnlyTimeInBedIsShownAsInBedNeverAsSleep() async {
        let health = InBedHealth()
        health.inBed = [Self.sample("BED", G.at(-1, 23), G.at(0, 7))]
        let harness = Harness { $0.healthChoices = HealthChoices(readSleep: true); $0.onboarding.permissionStatus = .granted }
        harness.now = now
        let engine = HealthSyncEngine(provider: health, host: harness.host)
        guard case .appliedSleep = await engine.readSleepChanges() else { Issue.record("not applied"); return }
        let state = harness.state

        // Stored apart from sleep, labelled, 480 minutes.
        #expect(state.sleeps.isEmpty)
        #expect(state.timeInBed.map(\.id) == ["healthkit:inbed:bed"])
        #expect(state.timeInBed.map { G.minutes($0.end - $0.start) } == [480])
        #expect(SleepEpisodes.build(state.sleeps, now: now, clock: G.utc).isEmpty)

        // Never "No recent sleep found": the status names time in bed.
        #expect(state.healthSync.importedCount == 0)
        #expect(state.healthSync.lastMessage == InBed.onlyInBedMessage)
        #expect(state.healthSync.lastMessage != HealthImport.noSleepMessage)
        let status = SleepDataStatus.describe(onboarding: state.onboarding, healthSync: state.healthSync, demoMode: false, healthAvailable: true, hasTimeInBed: true)
        #expect(status.state == "Time in bed only" && status.detail == InBed.onlyInBedMessage)

        // The Sleep and Summary cards show it as In bed.
        let signal = SleepModel.recentNightSignal(sleeps: state.sleeps, targetSleepHours: 8, now: now, clock: G.utc, text: fixtureText, timeInBed: state.timeInBed)
        #expect(signal.label == "In bed" && signal.value == "8h 0m" && signal.status == .observed)
        #expect(signal.context.hasSuffix("Time in bed from Health, not counted as sleep"))
        #expect(!signal.context.localizedCaseInsensitiveContains("target"))
        let summary = SummarySignals.sleep(sleeps: state.sleeps, targetSleepHours: 8, now: now, clock: G.utc, text: fixtureText, timeInBed: state.timeInBed)
        #expect(summary.id == "sleep" && summary.label == "In bed")
        for line in [signal.context, InBed.onlyInBedMessage, summary.context] { #expect(CopyRules.violations(in: line).isEmpty) }

        // The model never counts it: no recent sleep, no score.
        let estimate = Summary.estimateAlertness(at: now, doses: [], sleeps: state.sleeps, inputs: EstimateInputs(halfLifeHours: 5, targetSleepHours: 8, clock: G.utc))
        #expect(estimate == .needsSleep)
        #expect(RecentSleep.summarize(state.sleeps, targetHours: 8, now: now, clock: G.utc).asleepLast24hMs == 0)
    }

    @Test func asleepDataForTheSameNightWinsOverTimeInBed() {
        let bed = [TimeInBed(id: "healthkit:inbed:a", start: G.at(-1, 22, 30), end: G.at(0, 7, 30))]
        let sleeps = [G.health("w", G.at(-1, 23), G.at(0, 7))]
        #expect(InBed.uncovered(bed, sleeps: sleeps, now: now).isEmpty)
        let signal = SleepModel.recentNightSignal(sleeps: sleeps, targetSleepHours: nil, now: now, clock: G.utc, text: fixtureText, timeInBed: bed)
        #expect(signal.label == "Most Recent Sleep")
    }

    @Test func eachReadReplacesTheWindowAndAFailureKeepsWhatWasStored() async {
        let health = InBedHealth()
        health.inBed = [Self.sample("A", G.at(-2, 23), G.at(-1, 7)), Self.sample("B", G.at(-1, 23), G.at(0, 7))]
        let harness = Harness { $0.healthChoices = HealthChoices(readSleep: true) }
        harness.now = now
        let engine = HealthSyncEngine(provider: health, host: harness.host)
        _ = await engine.readSleepChanges()
        #expect(harness.state.timeInBed.map(\.id) == ["healthkit:inbed:b", "healthkit:inbed:a"])

        // Deleted in Health: gone here too.
        health.inBed.removeFirst()
        _ = await engine.readSleepChanges()
        #expect(harness.state.timeInBed.map(\.id) == ["healthkit:inbed:b"])

        // A failed read changes nothing and doesn't fail the sleep read.
        health.failInBed = true
        guard case .appliedSleep = await engine.readSleepChanges() else { Issue.record("sleep read failed"); return }
        #expect(harness.state.timeInBed.map(\.id) == ["healthkit:inbed:b"])
    }

    @Test func nothingIsReadWithSleepOffOrInSampleData() async {
        let health = InBedHealth()
        health.inBed = [Self.sample("A", G.at(-1, 23), G.at(0, 7))]
        let off = Harness()
        _ = await HealthSyncEngine(provider: health, host: off.host).readSleepChanges()
        let sample = Harness { $0.healthChoices = HealthChoices(readSleep: true); $0.demoMode = true }
        _ = await HealthSyncEngine(provider: health, host: sample.host).readSleepChanges()
        #expect(health.inBedReads == 0)
        #expect(off.state.timeInBed.isEmpty && sample.state.timeInBed.isEmpty)
    }

    @Test func storedTimeInBedRoundTripsIsNormalisedAndErased() throws {
        var state = AppState()
        state.replaceTimeInBed([Self.sample("A", G.at(-1, 23), G.at(0, 7)), Self.sample("OLD", G.at(-40, 23), G.at(-39, 7)),
                                HealthSleepSample(start: G.at(0, 1), end: G.at(0, 1))], now: now)
        // Only the window and valid intervals are kept.
        #expect(state.timeInBed.map(\.id) == ["healthkit:inbed:a"])
        #expect(state.timeInBed.first?.sourceName == "iPhone")
        let decoded = try JSONDecoder().decode(AppState.self, from: StateMigration.encode(state))
        #expect(decoded == state)
        // Older files have none.
        let older = try JSONDecoder().decode(AppState.self, from: Data(#"{"schemaVersion":2}"#.utf8))
        #expect(older.timeInBed.isEmpty)
        // Undateable records are dropped like any other record.
        var damaged = state
        damaged.timeInBed.append(TimeInBed(id: "healthkit:inbed:huge", start: 1e300, end: 2e300))
        #expect(damaged.droppingInvalidTimes().timeInBed == state.timeInBed)
        // Delete All Records removes it.
        state.deleteAllData()
        #expect(state.timeInBed.isEmpty)
    }
}
