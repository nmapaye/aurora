import Foundation
import Testing
@testable import AuroraCore

private let utc = LocalClock(timeZone: TimeZone(identifier: "UTC")!)
private let pacific = LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
private let now: Millis = 1_790_527_260_000 // 2026-09-27 16:41 UTC
/// 2026-11-01 08:00 UTC: 1:00 AM PDT, an hour before Los Angeles falls back.
private let fallBack: Millis = 1_793_520_000_000

private func inputs(_ clock: LocalClock) -> EstimateInputs {
    EstimateInputs(halfLifeHours: 5, targetSleepHours: 8, clock: clock)
}

@Suite struct EnergyEstimateTests {
    @Test func matchesTheExistingEstimateForEveryFixtureProbe() throws {
        var probes = 0
        for context in try ParityTests.contexts() {
            for probe in context.scenario.list("alertness") {
                let t = try #require(probe.double("t"))
                let existing = Summary.estimateAlertness(at: t, doses: context.doses, sleeps: context.sleeps, inputs: context.inputs)
                let energy = EnergyEstimate.capture(at: t, doses: context.doses, sleeps: context.sleeps, inputs: context.inputs)
                #expect(energy.modeledScore == existing.score)
                #expect(energy.timeZoneIdentifier == context.clock.timeZone.identifier)
                switch existing {
                case .needsSleep:
                    #expect(energy.contributions.isEmpty && energy.unroundedScore == nil)
                    #expect(energy.missingInputs.contains(.recentSleep))
                case .estimated(let score, let hours, let sample):
                    let raw = Alertness.score(at: t, doses: context.doses, sleeps: context.sleeps, halfLifeHours: 5, targetSleepHours: 8, clock: context.clock)
                    #expect(energy.unroundedScore == raw)
                    #expect(jsRoundInt(try #require(energy.unroundedScore)) == score)
                    #expect(energy.contributions.map(\.kind) == EnergyContribution.Kind.allCases)
                    #expect(energy.sleepHoursLast24 == hours)
                    #expect(energy.includesSample == sample)
                    #expect(!energy.missingInputs.contains(.recentSleep))
                }
                probes += 1
            }
        }
        #expect(probes > 0)
    }

    @Test func missingSleepHasNoScoreInBothZones() {
        let doses = [Dose(id: "a", timestamp: now - hourMs, mg: 95)]
        let sleeps = [SleepSession(id: "manual:sleep:1:a", start: now - 40 * hourMs, end: now - 32 * hourMs)]
        for clock in [utc, pacific] {
            let energy = EnergyEstimate.capture(at: now, doses: doses, sleeps: sleeps, inputs: inputs(clock))
            #expect(Summary.estimateAlertness(at: now, doses: doses, sleeps: sleeps, inputs: inputs(clock)) == .needsSleep)
            #expect(energy.modeledScore == nil && energy.contributions.isEmpty)
            #expect(energy.missingInputs == [.recentSleep])
            #expect(energy.summary.hasPrefix("Modeled alertness unavailable."))
        }
    }

    @Test func snapshotRecordsItsContextAndRoundTrips() throws {
        let sleeps = [SleepSession(id: "demo:sleep:1", start: now - 9 * hourMs, end: now - 2 * hourMs)]
        let energy = EnergyEstimate.capture(at: now, doses: [], sleeps: sleeps, inputs: inputs(pacific))
        #expect(energy.version == EnergyEstimate.currentVersion)
        #expect(energy.modelVersion == "alertness-1")
        #expect(energy.capturedAt == now && energy.timeZoneIdentifier == "America/Los_Angeles")
        #expect(energy.includesSample)
        #expect(energy.missingInputs == [.recentCaffeine])
        #expect(energy.limitations == EnergyLimitation.allCases)
        let decoded = try JSONDecoder().decode(EnergyEstimate.self, from: JSONEncoder().encode(energy))
        #expect(decoded == energy)
    }

    @Test func timeOfDayFollowsTheLocalClockAcrossFallBack() {
        let sleeps = [SleepSession(id: "manual:sleep:1:a", start: fallBack - 6 * hourMs, end: fallBack - 3 * hourMs)]
        // 1:30 AM PDT and 1:30 AM PST are an hour apart and share the local hour.
        let first = EnergyEstimate.capture(at: fallBack + 30 * minuteMs, doses: [], sleeps: sleeps, inputs: inputs(pacific))
        let second = EnergyEstimate.capture(at: fallBack + 90 * minuteMs, doses: [], sleeps: sleeps, inputs: inputs(pacific))
        #expect(first.contributions[1].term == second.contributions[1].term)
        let firstUTC = EnergyEstimate.capture(at: fallBack + 30 * minuteMs, doses: [], sleeps: sleeps, inputs: inputs(utc))
        let secondUTC = EnergyEstimate.capture(at: fallBack + 90 * minuteMs, doses: [], sleeps: sleeps, inputs: inputs(utc))
        #expect(firstUTC.contributions[1].term != secondUTC.contributions[1].term)
    }

    @Test func publicTextFollowsCopyRules() {
        let sleeps = [SleepSession(id: "manual:sleep:1:a", start: now - 9 * hourMs, end: now - 2 * hourMs)]
        let energy = EnergyEstimate.capture(at: now, doses: [], sleeps: sleeps, inputs: inputs(utc))
        let texts = [energy.summary, EnergyEstimate.title, EnergyProjection.futureAssumption, EnergyCheckIn.scaleLabel, EnergyCheckIn.kindLabel]
            + EnergyMissingInput.allCases.map(\.text) + EnergyLimitation.allCases.map(\.text)
        for text in texts {
            #expect(CopyRules.violations(in: text).isEmpty, "\(text)")
            #expect(!text.contains("%"))
        }
        #expect(EnergyEstimate.title == "Modeled alertness")
    }
}

@Suite struct EnergyProjectionTests {
    let sleeps = [SleepSession(id: "manual:sleep:1:a", start: now - 10 * hourMs, end: now - 2 * hourMs)]
    let doses = [Dose(id: "a", timestamp: now - hourMs, mg: 95)]

    @Test func coversTwentyFourHoursEveryThirtyMinutesWithACurrentMarker() {
        let projection = EnergyProjection.build(now: now, doses: doses, sleeps: sleeps, inputs: inputs(pacific))
        #expect(projection.points.count == 50) // 49 grid points plus now.
        #expect(projection.points.first?.t == (now / EnergyProjection.stepMs).rounded(.down) * EnergyProjection.stepMs - 12 * hourMs)
        #expect(projection.points.last!.t - projection.points.first!.t == 24 * hourMs)
        #expect(projection.points.map(\.t) == projection.points.map(\.t).sorted())
        #expect(projection.current.t == now && projection.current.kind == .current)
        #expect(projection.points.filter { $0.kind == .current }.count == 1)
        #expect(projection.points.allSatisfy { $0.kind == ($0.t < now ? .modeledPast : ($0.t == now ? .current : .projected)) })
        let snapshot = EnergyEstimate.capture(at: now, doses: doses, sleeps: sleeps, inputs: inputs(pacific))
        #expect(projection.current.modeledScore == snapshot.modeledScore)
    }

    @Test func nowOnTheGridIsNotDuplicated() {
        let onGrid = (now / EnergyProjection.stepMs).rounded(.down) * EnergyProjection.stepMs
        let projection = EnergyProjection.build(now: onGrid, doses: doses, sleeps: sleeps, inputs: inputs(utc))
        #expect(projection.points.count == 49)
        #expect(projection.currentIndex == 24 && projection.current.t == onGrid)
    }

    @Test func usesOnlyRecordsKnownAtCaptureAndAddsNothingAhead() {
        let base = EnergyProjection.build(now: now, doses: doses, sleeps: sleeps, inputs: inputs(utc))
        let laterDose = Dose(id: "later", timestamp: now + 2 * hourMs, mg: 200)
        let unfinishedSleep = SleepSession(id: "healthkit:sleep:x", start: now - hourMs, end: now + 3 * hourMs)
        let withFuture = EnergyProjection.build(now: now, doses: doses + [laterDose], sleeps: sleeps + [unfinishedSleep], inputs: inputs(utc))
        #expect(withFuture.points == base.points)
        for point in base.points {
            let expected = EnergyEstimate.capture(at: point.t, doses: doses, sleeps: sleeps, inputs: inputs(utc))
            #expect(point.modeledScore == expected.modeledScore)
        }
        // With no further sleep assumed, the far end loses its recent sleep.
        let late = EnergyProjection.build(now: now + 14 * hourMs, doses: doses, sleeps: sleeps, inputs: inputs(utc))
        #expect(late.points.last?.modeledScore == nil)
        #expect(late.points.last?.kind == .projected)
    }

    @Test func spacingStaysThirtyMinutesAcrossFallBackAndRoundTrips() throws {
        let sleeps = [SleepSession(id: "demo:sleep:1", start: fallBack - 8 * hourMs, end: fallBack - hourMs)]
        let projection = EnergyProjection.build(now: fallBack, doses: [], sleeps: sleeps, inputs: inputs(pacific))
        let times = projection.points.map(\.t)
        #expect(zip(times, times.dropFirst()).allSatisfy { $1 - $0 == EnergyProjection.stepMs })
        #expect(projection.points.contains { $0.includesSample })
        #expect(projection.timeZoneIdentifier == "America/Los_Angeles")
        let decoded = try JSONDecoder().decode(EnergyProjection.self, from: JSONEncoder().encode(projection))
        #expect(decoded == projection)
        #expect(EnergyProjection.build(now: fallBack, doses: [], sleeps: sleeps, inputs: inputs(pacific)) == projection)
    }
}

@Suite struct EnergyCheckInTests {
    @Test func validatesTheLabeledScaleAndTime() {
        #expect(EnergyCheckIn.validate(rating: 0, recordedAt: now, now: now).message != nil)
        #expect(EnergyCheckIn.validate(rating: 6, recordedAt: now, now: now).message != nil)
        #expect(EnergyCheckIn.validate(rating: 3, recordedAt: now + 1, now: now) == .invalid("Time cannot be in the future."))
        #expect(EnergyCheckIn.validate(rating: 3, recordedAt: .nan, now: now).message != nil)
        #expect(EnergyCheckIn.validate(rating: 1, recordedAt: now, now: now) == .valid)
        #expect(EnergyCheckIn.scale.map { EnergyCheckIn.label(forRating: $0) ?? "" } == ["Very low", "Low", "Moderate", "High", "Very high"])
        #expect(EnergyCheckIn.label(forRating: 0) == nil)
    }

    @Test func appStateStoresValidCheckInsNewestFirst() {
        var state = AppState()
        let older = EnergyCheckIn(id: RecordID.newEnergyCheckInID(now: now - hourMs, entropy: "a"), recordedAt: now - hourMs, rating: 2)
        let newer = EnergyCheckIn(id: RecordID.newEnergyCheckInID(now: now, entropy: "b"), recordedAt: now, rating: 4, note: "after walk")
        #expect(older.id == "checkin:\(Int64(now - hourMs)):a")
        #expect(state.addEnergyCheckIn(older, now: now) == .valid)
        #expect(state.addEnergyCheckIn(newer, now: now) == .valid)
        #expect(state.addEnergyCheckIn(newer, now: now) != .valid)
        #expect(state.addEnergyCheckIn(EnergyCheckIn(id: "checkin:x", recordedAt: now, rating: 9), now: now) != .valid)
        #expect(state.energyCheckIns == [newer, older])
        state.removeEnergyCheckIn(id: older.id)
        #expect(state.energyCheckIns == [newer])
        state.deleteAllData()
        #expect(state.energyCheckIns.isEmpty)
    }

    @Test func checkInsAreNotPartOfTheModel() {
        let sleeps = [SleepSession(id: "manual:sleep:1:a", start: now - 9 * hourMs, end: now - 2 * hourMs)]
        var state = AppState()
        state.sleeps = sleeps
        let before = EnergyEstimate.capture(at: now, doses: state.doses, sleeps: state.sleeps, inputs: inputs(utc))
        state.addEnergyCheckIn(EnergyCheckIn(id: "checkin:1:a", recordedAt: now, rating: 1), now: now)
        #expect(EnergyEstimate.capture(at: now, doses: state.doses, sleeps: state.sleeps, inputs: inputs(utc)) == before)
    }

    @Test func oldFilesDecodeAndAStoredOutOfRangeRatingDoesNotBreakTheState() throws {
        let old = try JSONDecoder().decode(AppState.self, from: Data(#"{"schemaVersion":1,"doses":[]}"#.utf8))
        #expect(old.energyCheckIns.isEmpty && old.healthLedger == .empty && old.schemaVersion == 1)
        #expect(try StateMigration.storedVersion(Data("{}".utf8)) == 1)
        let odd = try JSONDecoder().decode(AppState.self, from: Data(#"{"schemaVersion":2,"energyCheckIns":[{"id":"checkin:1:a","recordedAt":1,"rating":42}]}"#.utf8))
        #expect(odd.energyCheckIns.first?.rating == 42)
        #expect(odd.energyCheckIns.first?.validate(now: now) != .valid)
    }
}

@Suite struct HealthCaffeineTests {
    func sample(_ uuid: String, at t: Millis = now - hourMs, mg: Double = 80, bundle: String = "com.example.tracker", sync: String? = nil) -> HealthCaffeineSample {
        HealthCaffeineSample(
            provenance: HealthSampleProvenance(sampleUUID: uuid, sourceBundleIdentifier: bundle, sourceName: "Tracker", syncIdentifier: sync, syncVersion: sync == nil ? nil : 1),
            timestamp: t, mg: mg
        )
    }

    @Test func identityIsTheSampleUUIDNeverTimeAndAmount() {
        var state = AppState()
        state.addDose(Dose(id: "manual-1", timestamp: now - hourMs, mg: 80, source: "Drip"))
        let a = sample("AAAA-1"), b = sample("bbbb-2")
        let result = state.applyHealthCaffeine(HealthCaffeineChanges(added: [a, b], deletedSampleUUIDs: [], anchor: Data([1])), now: now)
        #expect(result.upserted == 2)
        #expect(state.doses.map(\.id) == ["manual-1", "healthkit:caffeine:aaaa-1", "healthkit:caffeine:bbbb-2"])
        #expect(state.doses[1].health?.sourceBundleIdentifier == "com.example.tracker")
        #expect(state.doses[1].health?.sampleUUID == "aaaa-1")
        #expect(state.healthLedger.anchor(for: .caffeine)?.data == Data([1]))

        var edited = a
        edited.mg = 120
        state.applyHealthCaffeine(HealthCaffeineChanges(added: [edited], deletedSampleUUIDs: ["BBBB-2"], anchor: Data([2])), now: now)
        #expect(state.doses.map(\.id) == ["manual-1", "healthkit:caffeine:aaaa-1"])
        #expect(state.doses[1].mg == 120)
        #expect(state.healthLedger.anchors.count == 1 && state.healthLedger.anchor(for: .caffeine)?.data == Data([2]))
    }

    @Test func ownExportsAndInvalidSamplesAreNotImported() {
        var state = AppState()
        let result = state.applyHealthCaffeine(HealthCaffeineChanges(added: [
            sample("1", bundle: HealthOrigin.appBundleIdentifier),
            sample("2", sync: HealthOrigin.syncIdentifier(forDoseID: "x")),
            sample("3", mg: 0),
            sample("4", at: .nan),
        ], deletedSampleUUIDs: [], anchor: Data()), now: now)
        #expect(state.doses.isEmpty)
        #expect(result.skippedOwn == 2 && result.rejected == 2)
    }

    @Test func healthCaffeineIsReadOnlyAtEveryMutation() {
        var state = AppState()
        state.applyHealthCaffeine(HealthCaffeineChanges(added: [sample("u1")], deletedSampleUUIDs: [], anchor: Data()), now: now)
        let imported = state.doses[0]
        state.updateDose(id: imported.id, timestamp: 1, mg: 1, source: "Tea", note: "x")
        state.updateDose(id: imported.id, with: Dose(id: "", timestamp: 2, mg: 2))
        state.removeDose(id: imported.id)
        #expect(state.doses == [imported])
        #expect(!CaffeineLog.isEditable(imported))
        #expect(CaffeineLog.sourceLabel(imported) == "Health")
        #expect(CaffeineLog.describe(imported) { _ in "T" }.contains("Health, read-only"))
        #expect(state.enqueueHealthExport(.saveCaffeine, doseID: imported.id, now: now, id: "act") == nil)
        #expect(state.enqueueHealthExport(.saveCaffeine, doseID: "demo:dose:1", now: now, id: "act") == nil)
    }

    @Test func manualDosesKeepTheirStoredKeys() throws {
        let dose = Dose(id: "m", timestamp: 1, mg: 95, source: "Drip", note: "n")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dose)) as? [String: Any]
        #expect(object.map { Set($0.keys) } == ["id", "timestamp", "mg", "source", "note"])
    }

    @Test func ledgerTracksOwnExportsPendingActionsAndOutcomes() throws {
        var state = AppState()
        state.addDose(Dose(id: "m1", timestamp: now, mg: 95))
        #expect(state.enqueueHealthExport(.deleteCaffeine, doseID: "m1", now: now, id: "d0") == nil)
        let queuedSave = state.enqueueHealthExport(.saveCaffeine, doseID: "m1", now: now, id: "s1")
        let save = try #require(queuedSave)
        #expect(save.syncIdentifier == "com.nmapaye.aurora.dose.m1" && save.syncVersion == 1)
        state.healthLedger.finish(actionID: "s1", result: .failed, message: "Offline", now: now)
        #expect(state.healthLedger.pendingActions.first?.attempts == 1)
        state.healthLedger.finish(actionID: "s1", result: .succeeded, sampleUUID: "ABC", now: now + 1)
        #expect(state.healthLedger.pendingActions.isEmpty)
        #expect(state.healthLedger.ownExport(forDoseID: "m1") == HealthOwnExport(doseID: "m1", syncIdentifier: save.syncIdentifier, syncVersion: 1, sampleUUID: "abc", exportedAt: now + 1))
        let queuedDelete = state.enqueueHealthExport(.deleteCaffeine, doseID: "m1", now: now + 2, id: "d1")
        let delete = try #require(queuedDelete)
        #expect(delete.syncVersion == 2)
        state.healthLedger.finish(actionID: "d1", result: .succeeded, now: now + 3)
        #expect(state.healthLedger.ownExports.isEmpty)
        #expect(state.healthLedger.outcomes.map(\.result) == [.failed, .succeeded, .succeeded])
        let decoded = try JSONDecoder().decode(HealthSyncLedger.self, from: JSONEncoder().encode(state.healthLedger))
        #expect(decoded == state.healthLedger)
        state.deleteAllData()
        #expect(state.healthLedger == .empty)
    }

    @Test func providerDefaultsRefuseUndeclaredOperations() async throws {
        struct SleepOnly: HealthDataProvider {
            var capabilities: HealthCapabilities { [.readSleep] }
            var isAvailable: Bool { true }
            func sleepSamples(from start: Millis, to end: Millis) async throws -> [HealthSleepSample] { [] }
        }
        let provider = SleepOnly()
        #expect(try await provider.sleepSamples(from: 0, to: 1) == [])
        await #expect(throws: HealthProviderError.unsupported("writeOwnCaffeine")) {
            try await provider.saveOwnCaffeine(HealthCaffeineWrite(doseID: "m", timestamp: 0, mg: 1, syncIdentifier: "s", syncVersion: 1))
        }
        await #expect(throws: HealthProviderError.unsupported("readCaffeineChanges")) { try await provider.caffeineChanges(after: nil) }
        await #expect(throws: HealthProviderError.unsupported("deleteOwnCaffeine")) { try await provider.deleteOwnCaffeine(syncIdentifier: "s") }
        await #expect(throws: HealthProviderError.unsupported("observeChanges")) { _ = try await provider.startObserving([.caffeine]) { _ in } }
    }
}

@Suite struct StateMigrationTests {
    struct WriteFailure: Error {}

    let directory: URL
    var stateURL: URL { directory.appendingPathComponent("state.json") }
    var sourceURL: URL { directory.appendingPathComponent("state.v1-source.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("aurora-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// A file as the version-1 build wrote it: sorted keys, no new fields.
    func v1Data() throws -> Data {
        var state = AppState()
        state.doses = [
            Dose(id: "lx1-abc", timestamp: 1_790_000_000_000, mg: 95, source: "Drip", note: "after run"),
            Dose(id: "demo:dose:1", timestamp: 1_790_000_100_000, mg: 60),
        ]
        state.sleeps = [SleepSession(id: "healthkit:sleep:1789960000000:1789990000000", start: 1_789_960_000_000, end: 1_789_990_000_000)]
        state.prefs.cutoffHour = 14
        state.appearanceMode = .dark
        state.healthSync = HealthSync(lastSyncedAt: 1_790_000_000_000, importedCount: 3, importStatus: .succeeded)
        var object = try #require(JSONSerialization.jsonObject(with: StateMigration.encode(state)) as? [String: Any])
        object["energyCheckIns"] = nil
        object["healthLedger"] = nil
        object["schemaVersion"] = 1
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func files(failingWritesTo name: String) -> StateMigration.Files {
        let standard = StateMigration.Files.standard
        return StateMigration.Files(
            read: standard.read,
            write: { data, url in
                if url.lastPathComponent == name { throw WriteFailure() }
                try standard.write(data, url)
            },
            exists: standard.exists
        )
    }

    func doses(in data: Data) throws -> NSArray {
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(object["doses"] as? NSArray)
    }

    @Test func migratesVersionOneAndRetainsTheVerifiedSource() throws {
        let original = try v1Data()
        try original.write(to: stateURL)
        let loaded = try #require(try StateMigration.load(directory: directory))
        #expect(loaded.migratedFrom == 1 && loaded.original == original)
        #expect(loaded.state.schemaVersion == 2)
        #expect(try Data(contentsOf: sourceURL) == original)
        let v1 = try JSONDecoder().decode(AppState.self, from: original)
        #expect(loaded.state.doses == v1.doses && loaded.state.sleeps == v1.sleeps && loaded.state.prefs == v1.prefs)
        #expect(loaded.state.energyCheckIns.isEmpty && loaded.state.healthLedger == .empty)
        let saved = try Data(contentsOf: stateURL)
        #expect(try JSONDecoder().decode(AppState.self, from: saved) == loaded.state)
        #expect(try doses(in: saved).isEqual(try doses(in: original)))

        let again = try #require(try StateMigration.load(directory: directory))
        #expect(again.migratedFrom == nil && again.state == loaded.state)
        #expect(try Data(contentsOf: sourceURL) == original)
    }

    @Test func aFileWithoutAVersionIsMigratedAsVersionOne() throws {
        try Data(#"{"doses":[{"id":"a","mg":95,"timestamp":1}]}"#.utf8).write(to: stateURL)
        let loaded = try #require(try StateMigration.load(directory: directory))
        #expect(loaded.migratedFrom == 1 && loaded.state.doses == [Dose(id: "a", timestamp: 1, mg: 95)])
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test func futureAndCorruptFilesFailClosedWithoutChanges() throws {
        let future = Data(#"{"schemaVersion":3,"doses":[{"id":"a","kind":"new"}]}"#.utf8)
        try future.write(to: stateURL)
        #expect(throws: StateMigration.Failure.unsupportedVersion(3)) { try StateMigration.load(directory: directory) }
        #expect(try Data(contentsOf: stateURL) == future)

        let corrupt = Data("{oops".utf8)
        try corrupt.write(to: stateURL)
        #expect(throws: StateMigration.Failure.undecodable) { try StateMigration.load(directory: directory) }
        #expect(try Data(contentsOf: stateURL) == corrupt)
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test func failedWritesKeepTheOriginalAndRetrySucceeds() throws {
        let original = try v1Data()
        try original.write(to: stateURL)

        #expect(throws: WriteFailure.self) { try StateMigration.load(directory: directory, files: files(failingWritesTo: "state.v1-source.json")) }
        #expect(try Data(contentsOf: stateURL) == original)
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))

        #expect(throws: WriteFailure.self) { try StateMigration.load(directory: directory, files: files(failingWritesTo: "state.json")) }
        #expect(try Data(contentsOf: stateURL) == original)
        #expect(try Data(contentsOf: sourceURL) == original)

        let retried = try #require(try StateMigration.load(directory: directory))
        #expect(retried.migratedFrom == 1 && retried.state.schemaVersion == 2)
        #expect(try Data(contentsOf: sourceURL) == original)
    }

    @Test func unverifiableSaveRestoresTheOriginal() throws {
        let original = try v1Data()
        try original.write(to: stateURL)
        let standard = StateMigration.Files.standard
        let garbling = StateMigration.Files(
            read: standard.read,
            write: { data, url in try standard.write(url.lastPathComponent == "state.json" && data != original ? Data("{".utf8) : data, url) },
            exists: standard.exists
        )
        #expect(throws: StateMigration.Failure.undecodable) { try StateMigration.load(directory: directory, files: garbling) }
        #expect(try Data(contentsOf: stateURL) == original)
    }

    @Test func aDifferentRetainedSourceIsNeverReplaced() throws {
        let original = try v1Data()
        try original.write(to: stateURL)
        let other = Data(#"{"schemaVersion":1,"doses":[]}"#.utf8)
        try other.write(to: sourceURL)
        #expect(throws: StateMigration.Failure.retainedSourceMismatch) { try StateMigration.load(directory: directory) }
        #expect(try Data(contentsOf: stateURL) == original)
        #expect(try Data(contentsOf: sourceURL) == other)
    }

    @Test func currentFilesAndMissingFilesAreNotTouched() throws {
        #expect(try StateMigration.load(directory: directory) == nil)
        let data = try StateMigration.encode(AppState())
        try data.write(to: stateURL)
        let loaded = try #require(try StateMigration.load(directory: directory))
        #expect(loaded.migratedFrom == nil && loaded.state == AppState())
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
    }
}

@MainActor
@Suite struct RefreshCoordinatorTests {
    actor Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var calls = 0

        func enter() async -> Int {
            calls += 1
            let call = calls
            await withCheckedContinuation { waiters.append($0) }
            return call
        }

        var waiting: Int { waiters.count }

        func releaseAll() {
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    @MainActor final class Applied {
        var values: [Int] = []
    }

    func waitFor(_ gate: Gate, waiting count: Int) async {
        while await gate.waiting < count { await Task.yield() }
    }

    @Test func concurrentRequestsShareOneFetch() async {
        let gate = Gate(), applied = Applied()
        let coordinator = RefreshCoordinator<Int>(fetch: { await gate.enter() }, apply: { applied.values.append($0) })
        let first = Task { await coordinator.refresh() }
        await waitFor(gate, waiting: 1)
        let joined = Applied()
        // Both run on the main actor, so once the flag is set the second call
        // has already joined the running refresh.
        let second = Task {
            joined.values.append(0)
            return await coordinator.refresh()
        }
        while joined.values.isEmpty { await Task.yield() }
        #expect(coordinator.isRefreshing)
        await gate.releaseAll()
        #expect(await first.value == .applied)
        #expect(await second.value == .applied)
        #expect(await gate.calls == 1 && applied.values == [1])
        #expect(!coordinator.isRefreshing)
    }

    @Test func invalidationDiscardsALateResultEvenIfTheFetchIgnoresCancellation() async {
        let gate = Gate(), applied = Applied()
        let coordinator = RefreshCoordinator<Int>(fetch: { await gate.enter() }, apply: { applied.values.append($0) })
        let stale = Task { await coordinator.refresh() }
        await waitFor(gate, waiting: 1)
        coordinator.invalidate()
        #expect(coordinator.generation == 1 && !coordinator.isRefreshing)
        await gate.releaseAll()
        #expect(await stale.value == .discarded)
        #expect(applied.values.isEmpty)
    }

    @Test func aNewerRefreshWinsTheRace() async {
        let gate = Gate(), applied = Applied()
        let coordinator = RefreshCoordinator<Int>(fetch: { await gate.enter() }, apply: { applied.values.append($0) })
        let stale = Task { await coordinator.refresh() }
        await waitFor(gate, waiting: 1)
        coordinator.invalidate()
        let fresh = Task { await coordinator.refresh() }
        await waitFor(gate, waiting: 2)
        #expect(coordinator.isRefreshing)
        await gate.releaseAll()
        #expect(await stale.value == .discarded)
        #expect(await fresh.value == .applied)
        #expect(applied.values == [2])
        #expect(!coordinator.isRefreshing)
    }

    @Test func failuresAreReportedOnlyWhileCurrent() async {
        struct Offline: Error {}
        let applied = Applied()
        let failing = RefreshCoordinator<Int>(fetch: { throw Offline() }, apply: { applied.values.append($0) })
        guard case .failed = await failing.refresh() else {
            Issue.record("Expected a failure")
            return
        }
        let cancelled = RefreshCoordinator<Int>(fetch: {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return 1
        }, apply: { applied.values.append($0) })
        let task = Task { await cancelled.refresh() }
        while !cancelled.isRefreshing { await Task.yield() }
        cancelled.invalidate()
        #expect(await task.value == .discarded)
        #expect(applied.values.isEmpty)
    }
}
