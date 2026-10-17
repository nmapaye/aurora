import Foundation
import Testing
@testable import AuroraCore

// Frozen copies of the energy snapshot shape builds before October 2026
// decode (origin/main 73199d4; claude/ui-review d913d99 is the same shape),
// synthesized Codable as they were. Never update these to match current
// code: they stand in for an older build opening this build's saved
// conversation after a downgrade.
//
// Of the types a saved conversation holds, only `EnergyEstimate`'s
// `targetSleepHours` (Double to Double?) and `EnergyMissingInput` (new
// `sleepTarget` case) changed shape on this branch
// (`git diff origin/claude/ui-review -- AuroraCore/Sources`), so the message
// and card wrappers below keep only the path to the estimate; their other
// fields decode with unchanged types.

private enum LegacyContributionKindV1: String, Codable { case baseline, timeOfDay, caffeine, sleepDebt, inertia }

private struct LegacyEnergyContributionV1: Codable {
    var kind: LegacyContributionKindV1
    var term: Double
    var points: Double
}

private enum LegacyEnergyMissingInputV1: String, Codable { case recentSleep, recentCaffeine, caffeine }

private enum LegacyEnergyLimitationV1: String, Codable { case notMeasured, genericCircadian, halfLifeSetting, unmeasuredFactors }

private enum LegacyEnergyInputSourceV1: String, Codable { case manual, health, sample }

private struct LegacyEnergyEvidenceV1: Codable {
    struct CaffeineInput: Codable {
        var recordID: String
        var source: LegacyEnergyInputSourceV1
        var timestamp: Millis
        var mg: Double
        var activeMg: Double
        var healthSampleUUID: String?
        var healthSourceBundleIdentifier: String?
    }

    struct FadedCaffeine: Codable {
        var count: Int
        var activeMg: Double
        var latestTimestamp: Millis
        var includesSample: Bool
    }

    struct SleepInput: Codable {
        var recordID: String
        var source: LegacyEnergyInputSourceV1
        var start: Millis
        var end: Millis
        var hoursInWindow: Double
        var inLatestEpisode: Bool
    }

    var windowStart: Millis
    var activeCaffeineMg: Double
    var caffeine: [CaffeineInput]
    var fadedCaffeine: FadedCaffeine?
    var sleep: [SleepInput]
    var lastWakeAt: Millis?
}

private struct LegacyEnergyEstimateV1: Codable {
    var version: Int
    var modelVersion: String
    var capturedAt: Millis
    var timeZoneIdentifier: String
    var halfLifeHours: Double
    var targetSleepHours: Double
    var sleepHoursLast24: Double
    var modeledScore: Int?
    var contributions: [LegacyEnergyContributionV1]
    var missingInputs: [LegacyEnergyMissingInputV1]
    var includesSample: Bool
    var limitations: [LegacyEnergyLimitationV1]
    var evidence: LegacyEnergyEvidenceV1
}

private struct LegacyEnergySnapshotV1: Decodable {
    var version: Int
    var estimate: LegacyEnergyEstimateV1
}

private struct LegacyCardV1: Decodable {
    var title: String
    var energy: LegacyEnergySnapshotV1?
}

private struct LegacyConversationMessageV1: Decodable {
    var id: UUID
    var isUser: Bool
    var text: String
    var createdAt: Date
    var card: LegacyCardV1?
}

private struct LegacyConversationStateV1: Decodable {
    var version: Int
    var messages: [LegacyConversationMessageV1]
}

@Suite("Energy snapshot downgrade compatibility")
struct EnergySnapshotCompatibilityTests {
    typealias G = SleepGolden
    let now = SleepGolden.at(0, 12)

    /// A real energy card from this build, as the conversation saves it.
    private func conversation(_ setup: (inout AppState) -> Void) throws -> (ConversationState, EnergyEstimate) {
        var state = AppState()
        setup(&state)
        let card = AssistantCards.make(.energy, state: state, now: now, clock: G.utc, text: fixtureText)
        let estimate = try #require(card.energy?.estimate)
        var conversation = ConversationState()
        conversation.messages = [ConversationMessage(text: "How is my energy?", isUser: true), ConversationMessage(text: card.title, card: card)]
        return (conversation, estimate)
    }

    private func olderBuildReads(_ conversation: ConversationState) throws -> LegacyEnergyEstimateV1 {
        // ConversationStore saves with a plain JSONEncoder.
        let data = try JSONEncoder().encode(conversation)
        let old = try JSONDecoder().decode(LegacyConversationStateV1.self, from: data)
        #expect(old.messages.count == 2)
        return try #require(old.messages.last?.card?.energy?.estimate)
    }

    private func nights(_ count: Int) -> [SleepSession] {
        (0..<count).map { G.health("n\($0)", G.at(-$0 - 1, 23), G.at(-$0, 7)) }
    }

    @Test func noTargetAndTooFewNightsStillOpensInAnOlderBuild() throws {
        let (conversation, estimate) = try conversation { $0.sleeps = nights(1) }
        #expect(estimate.missingInputs.contains(.sleepTarget) && estimate.targetSleepHours == nil)
        let old = try olderBuildReads(conversation)
        #expect(old.targetSleepHours == EnergyEstimate.LegacyPlaceholder.targetSleepHours)
        #expect(old.missingInputs.map(\.rawValue) == estimate.missingInputs.filter { $0 != .sleepTarget }.map(\.rawValue))
        #expect(old.modeledScore == estimate.modeledScore)
        // This build reads its own file back exactly.
        let back = try JSONDecoder().decode(ConversationState.self, from: JSONEncoder().encode(conversation))
        #expect(back == conversation)
    }

    @Test func aUsualSleepBaselineIsTheOlderBuildsPlaceholder() throws {
        let (conversation, estimate) = try conversation { $0.sleeps = nights(8) }
        let usual = try #require(estimate.usualSleep)
        #expect(estimate.targetSleepHours == nil)
        #expect(try olderBuildReads(conversation).targetSleepHours == usual.hours)
        let back = try JSONDecoder().decode(ConversationState.self, from: JSONEncoder().encode(conversation))
        #expect(back.messages.last?.card?.energy?.estimate == estimate)
        #expect(back.messages.last?.card?.energy?.estimate.targetSleepHours == nil)
    }

    @Test func aChosenTargetIsWhatTheOlderBuildSees() throws {
        let (conversation, estimate) = try conversation { $0.sleeps = nights(2); $0.prefs.targetSleep = 7.5 }
        #expect(estimate.targetSleepHours == 7.5)
        #expect(try olderBuildReads(conversation).targetSleepHours == 7.5)
        let back = try JSONDecoder().decode(ConversationState.self, from: JSONEncoder().encode(conversation))
        #expect(back == conversation)
    }

    @Test func olderSnapshotsStillDecode() throws {
        // A snapshot an older build wrote: no marker, legacy keys are real.
        let (conversation, estimate) = try conversation { $0.sleeps = nights(2); $0.prefs.targetSleep = 8 }
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(estimate)) as? [String: Any])
        for key in ["legacyPlaceholders", "chosenTargetSleepHours", "allMissingInputs"] { object.removeValue(forKey: key) }
        object["targetSleepHours"] = 6.5
        let older = try JSONDecoder().decode(EnergyEstimate.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older.targetSleepHours == 6.5)
        #expect(older.missingInputs == estimate.missingInputs)
        _ = conversation
    }

    @Test func everyLegacyKeyIsWritten() throws {
        let (_, estimate) = try conversation { $0.sleeps = nights(1) }
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(estimate)) as? [String: Any])
        #expect(object["targetSleepHours"] as? Double == 8)
        #expect(object["legacyPlaceholders"] as? [String] == EnergyEstimate.placeholderKeys)
        #expect((object["missingInputs"] as? [String])?.contains("sleepTarget") == false)
        #expect((object["allMissingInputs"] as? [String])?.contains("sleepTarget") == true)
    }
}
