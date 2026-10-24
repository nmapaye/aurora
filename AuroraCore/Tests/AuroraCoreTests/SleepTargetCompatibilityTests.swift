import Foundation
import Testing
@testable import AuroraCore

/// Frozen copies of the Prefs shape builds before October 2026 decode
/// (origin/main 73199d4 and claude/ui-review d913d99), synthesized Codable
/// as they were. Never update these to match current code: they stand in for
/// an older build opening this build's file after a downgrade. The same
/// shape as the claims branch's `PrefsCompatibilityTests`.
private struct LegacyWakeReminderSettingsV1: Codable, Equatable {
    var enabled: Bool
    var offsetsMinutes: [Int]
    var usualWakeMinutes: Int
}

private struct LegacyRepeatDrinkSettingsV1: Codable, Equatable {
    var enabled: Bool
    var notify: Bool
}

private struct LegacyPrefsV1: Codable, Equatable {
    var halfLife: Double
    var targetSleep: Double
    var tz: String?
    var dailyLimitMg: Double
    var cutoffHour: Double
    var notifyCutoff: Bool
    var displayName: String?
    var favoriteDrinkIDs: [String]?
    var wakeReminders: LegacyWakeReminderSettingsV1?
    var repeatDrinks: LegacyRepeatDrinkSettingsV1?
}

/// The older AppState read prefs with `decodeIfPresent`: a prefs object that
/// fails to decode fails the whole file, which is then set aside as corrupt.
/// Its onboarding is the same shape this build writes.
private struct LegacyAppStateV1: Codable {
    var prefs: LegacyPrefsV1?
    var onboarding: Onboarding?
}

@Suite("Sleep target downgrade compatibility")
struct SleepTargetCompatibilityTests {
    private func file(_ target: Double?, skippedAtSetup: Bool = false) throws -> Data {
        var state = AppState()
        state.prefs.targetSleep = target
        if skippedAtSetup { state.onboarding.setupOutcomes = ["2": SetupOutcome.skipped.rawValue] }
        return try StateMigration.encode(state)
    }

    private func legacy(_ data: Data) throws -> LegacyAppStateV1 {
        try JSONDecoder().decode(LegacyAppStateV1.self, from: data)
    }

    @Test func anOlderBuildOpensAFileWithNoTargetSet() throws {
        let old = try #require(try legacy(file(nil)).prefs)
        #expect(old.targetSleep == Prefs.LegacyPlaceholder.targetSleep)
        #expect(old.halfLife == Prefs.defaultHalfLife && old.cutoffHour == 16 && old.dailyLimitMg == 400)
    }

    @Test func anOlderBuildSeesTheChosenTarget() throws {
        #expect(try #require(try legacy(file(7.5)).prefs).targetSleep == 7.5)
    }

    @Test func unsetStaysUnsetAndAChosenEightStaysChosen() throws {
        let unset = try JSONDecoder().decode(AppState.self, from: file(nil, skippedAtSetup: true))
        #expect(unset.prefs.targetSleep == nil)
        #expect(unset.prefs == AppState().prefs)
        // 8 chosen after "Not now" at setup: the marker keeps it chosen.
        let eight = try JSONDecoder().decode(AppState.self, from: file(8, skippedAtSetup: true))
        #expect(eight.prefs.targetSleep == 8)
        let written = String(decoding: try file(nil), as: UTF8.self)
        #expect(written.contains(#""legacyPlaceholders":["targetSleep"]"#))
        #expect(!written.contains("chosenTargetSleep"))
        #expect(String(decoding: try file(8), as: UTF8.self).contains(#""chosenTargetSleep":8"#))
    }

    @Test func thePlaceholderIsNeverReadBack() throws {
        let marked = #"{"halfLife":5,"targetSleep":8,"dailyLimitMg":400,"cutoffHour":16,"notifyCutoff":false,"legacyPlaceholders":["targetSleep"]}"#
        #expect(try JSONDecoder().decode(Prefs.self, from: Data(marked.utf8)).targetSleep == nil)
        let chosen = #"{"halfLife":5,"targetSleep":8,"chosenTargetSleep":6.5,"dailyLimitMg":400,"cutoffHour":16,"notifyCutoff":false,"legacyPlaceholders":["targetSleep"]}"#
        #expect(try JSONDecoder().decode(Prefs.self, from: Data(chosen.utf8)).targetSleep == 6.5)
        // Unmarked (an older build's file): the legacy key is the value.
        let older = #"{"halfLife":5,"targetSleep":7,"dailyLimitMg":400,"cutoffHour":16,"notifyCutoff":false}"#
        #expect(try JSONDecoder().decode(Prefs.self, from: Data(older.utf8)).targetSleep == 7)
    }

    /// An older build that opens a new file and saves it again drops the keys
    /// it doesn't know: the placeholder list, the chosen key and the
    /// `sleepTargetFormat` marker. The new build then reads it as an older
    /// build's file, so the existing migration applies: 8 h with "Not now" at
    /// setup goes back to unset, and any other stored target is kept.
    @Test func aFileReSavedByAnOlderBuildFollowsTheMigration() throws {
        let resavedUnset = try JSONEncoder().encode(try legacy(file(nil, skippedAtSetup: true)))
        #expect(!String(decoding: resavedUnset, as: UTF8.self).contains("legacyPlaceholders"))
        #expect(try JSONDecoder().decode(AppState.self, from: resavedUnset).prefs.targetSleep == nil)

        let resavedChosen = try JSONEncoder().encode(try legacy(file(6.5, skippedAtSetup: true)))
        #expect(try JSONDecoder().decode(AppState.self, from: resavedChosen).prefs.targetSleep == 6.5)
    }

    /// 8 h chosen after "Not now" at setup, then a downgrade that saves:
    /// the older build drops `sleepTargetFormat` and the `chosen…` key, so
    /// the file looks like one from before the target could be unset. It
    /// keeps `setupOutcomes` whole (`[String: String]` in every older build),
    /// so the choice is recorded there and the migration leaves it.
    @Test func anEightChosenAfterNotNowSurvivesAnOlderBuildsSave() throws {
        let resaved = try JSONEncoder().encode(try legacy(file(8, skippedAtSetup: true)))
        let text = String(decoding: resaved, as: UTF8.self)
        #expect(!text.contains("sleepTargetFormat") && !text.contains("chosenTargetSleep"))
        let back = try JSONDecoder().decode(AppState.self, from: resaved)
        #expect(back.prefs.targetSleep == 8)
        // Setup still reads as "Not now", in this build and the older one.
        #expect(back.onboarding.setupOutcomes == ["2": SetupOutcome.skipped.rawValue])
        #expect(try legacy(file(8, skippedAtSetup: true)).onboarding?.setupOutcome(.sleepTarget, displayName: nil) == .skipped)
        // Unset after "Not now" still goes back to unset.
        let unset = try JSONEncoder().encode(try legacy(file(nil, skippedAtSetup: true)))
        #expect(try JSONDecoder().decode(AppState.self, from: unset).prefs.targetSleep == nil)
    }

    /// The record of the choice never shows in the state: it is written from
    /// the target on save and read only by the migration.
    @Test func theRecordedChoiceRoundTripsInvisibly() throws {
        var state = AppState()
        state.prefs.targetSleep = 8
        state.onboarding.setupOutcomes = ["2": SetupOutcome.skipped.rawValue]
        #expect(try StateMigration.decode(StateMigration.encode(state)) == state)
        // Only 8 h after "Not now" needs it; every other file is unchanged.
        for (target, outcomes) in [(7.5, ["2": "skipped"]), (8, ["2": "answered"]), (nil, ["2": "skipped"])] as [(Double?, [String: String])] {
            var other = AppState()
            other.prefs.targetSleep = target
            other.onboarding.setupOutcomes = outcomes
            let object = try #require(try JSONSerialization.jsonObject(with: StateMigration.encode(other)) as? [String: Any])
            let onboarding = try #require(object["onboarding"] as? [String: Any])
            #expect(onboarding["setupOutcomes"] as? [String: String] == outcomes)
            #expect(try StateMigration.decode(StateMigration.encode(other)) == other)
        }
    }

    @Test func theCurrentShapeStillHasEveryKeyOlderBuildsRequire() throws {
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Prefs.defaults)) as? [String: Any])
        for key in ["halfLife", "targetSleep", "dailyLimitMg", "cutoffHour", "notifyCutoff"] {
            #expect(object[key] != nil, "\(key)")
        }
        #expect(object["legacyPlaceholders"] as? [String] == Prefs.placeholderKeys)
    }
}
