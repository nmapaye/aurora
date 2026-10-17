import Foundation
import Testing
@testable import AuroraCore

/// Frozen copies of the Prefs shape builds before October 2026 decode
/// (origin/main 73199d4 and claude/ui-review d913d99), synthesized Codable
/// as they were. Never update these to match current code: they stand in for
/// an older build opening this build's file after a downgrade.
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
private struct LegacyAppStateV1: Decodable {
    var prefs: LegacyPrefsV1?
}

struct PrefsCompatibilityTests {
    private func file(_ prefs: Prefs) throws -> Data {
        var state = AppState()
        state.prefs = prefs
        return try JSONEncoder().encode(state)
    }

    private func legacy(_ prefs: Prefs) throws -> LegacyPrefsV1 {
        try #require(try JSONDecoder().decode(LegacyAppStateV1.self, from: file(prefs)).prefs)
    }

    @Test func anOlderBuildOpensANewFileWithNothingSwitchedOn() throws {
        // Nothing chosen: placeholders only, and no reminder.
        let old = try legacy(.defaults)
        #expect(old.cutoffHour == 16 && old.dailyLimitMg == 400)
        #expect(!old.notifyCutoff)
        #expect(old.halfLife == Prefs.defaultHalfLife && old.targetSleep == Prefs.defaultTargetSleep)
        #expect(old.wakeReminders == nil && old.repeatDrinks == nil)

        // A reminder switched on without a time is still written off.
        var stray = Prefs.defaults
        stray.notifyCutoff = true
        #expect(try !legacy(stray).notifyCutoff)
    }

    @Test func anOlderBuildSeesTheChosenTimeAndReminders() throws {
        var prefs = Prefs.defaults
        prefs.cutoffHour = 14
        prefs.notifyCutoff = true
        prefs.displayName = "Sam"
        prefs.wakeReminders = WakeReminderSettings(enabled: true, offsetsMinutes: [60], usualWakeMinutes: 420)
        prefs.repeatDrinks = RepeatDrinkSettings(enabled: true, notify: false)
        let old = try legacy(prefs)
        #expect(old.cutoffHour == 14 && old.notifyCutoff && old.dailyLimitMg == 400)
        #expect(old.displayName == "Sam")
        #expect(old.wakeReminders == LegacyWakeReminderSettingsV1(enabled: true, offsetsMinutes: [60], usualWakeMinutes: 420))
        #expect(old.repeatDrinks == LegacyRepeatDrinkSettingsV1(enabled: true, notify: false))
    }

    @Test func newFilesRoundTripUnsetAndAChosenFour() throws {
        let unset = try JSONDecoder().decode(AppState.self, from: file(.defaults))
        #expect(unset.prefs.cutoffHour == nil && !unset.prefs.notifyCutoff)
        #expect(unset.prefs == .defaults)

        var four = Prefs.defaults
        four.cutoffHour = 16
        four.notifyCutoff = true
        let chosen = try JSONDecoder().decode(AppState.self, from: file(four))
        #expect(chosen.prefs.cutoffHour == 16 && chosen.prefs.notifyCutoff)
        #expect(chosen.prefs == four)

        let written = String(decoding: try file(.defaults), as: UTF8.self)
        #expect(written.contains("\"legacyPlaceholders\""))
        #expect(!written.contains("chosenCutoffHour"))
    }

    @Test func placeholdersAreNeverReadBack() throws {
        // A marked file whose placeholder says 13: the chosen key decides.
        let marked = #"{"halfLife":5,"targetSleep":8,"dailyLimitMg":1000,"cutoffHour":13,"notifyCutoff":true,"legacyPlaceholders":["cutoffHour","dailyLimitMg"]}"#
        let prefs = try JSONDecoder().decode(Prefs.self, from: Data(marked.utf8))
        #expect(prefs.cutoffHour == nil && !prefs.notifyCutoff)
        let chosen = #"{"halfLife":5,"targetSleep":8,"dailyLimitMg":1000,"cutoffHour":16,"chosenCutoffHour":13,"notifyCutoff":true,"legacyPlaceholders":["cutoffHour","dailyLimitMg"]}"#
        #expect(try JSONDecoder().decode(Prefs.self, from: Data(chosen.utf8)).cutoffHour == 13)
        // dailyLimitMg has no field to land in; re-encoding writes 400.
        let again = String(decoding: try JSONEncoder().encode(prefs), as: UTF8.self)
        #expect(again.contains("\"dailyLimitMg\":400") && !again.contains("1000"))
    }

    /// An older build that opens a new file and saves it again drops the
    /// keys it doesn't know, the marker included. The new build then reads
    /// the file as an older build's: the stored cutoff is kept, so this case
    /// keeps the 4 PM placeholder as a chosen time. The older build can't say
    /// it was a placeholder. Its reminder stays off, as written.
    @Test func aFileReSavedByAnOlderBuildFollowsTheMigrationRules() throws {
        let old = try legacy(.defaults)
        let resaved = try JSONEncoder().encode(old)
        #expect(!String(decoding: resaved, as: UTF8.self).contains("legacyPlaceholders"))
        let prefs = try JSONDecoder().decode(Prefs.self, from: resaved)
        #expect(prefs.cutoffHour == 16)
        #expect(!prefs.notifyCutoff && !prefs.cutoffReminderOn)

        // A time the person chose before downgrading survives too.
        var chosen = Prefs.defaults
        chosen.cutoffHour = 14
        chosen.notifyCutoff = true
        let back = try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(try legacy(chosen)))
        #expect(back.cutoffHour == 14 && back.notifyCutoff)
    }

    @Test func theCurrentShapeStillHasEveryKeyOlderBuildsRequire() throws {
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Prefs.defaults)) as? [String: Any])
        for key in ["halfLife", "targetSleep", "dailyLimitMg", "cutoffHour", "notifyCutoff"] {
            #expect(object[key] != nil, "\(key)")
        }
        #expect(Set(object["legacyPlaceholders"] as? [String] ?? []) == ["cutoffHour", "dailyLimitMg"])
    }
}
