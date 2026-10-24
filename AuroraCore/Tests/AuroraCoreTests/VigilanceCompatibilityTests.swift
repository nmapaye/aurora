import Foundation
import Testing
@testable import AuroraCore

/// Frozen copy of the Reaction Test session shape builds before #39 decode
/// and write (origin/claude/ui-review 3f5fb9e, origin/main 73199d4),
/// synthesized Codable as it was. Never update it to match current code: it
/// stands in for an older build opening this build's file after a downgrade.
private struct LegacyVigilanceSessionV1: Codable, Equatable {
    var id: String
    var startedAt: Millis
    var completedAt: Millis
    var durationMs: Millis
    var trialCount: Int
    var validReactionCount: Int
    var falseStartCount: Int
    var lapseCount: Int
    var medianReactionMs: Double?
    var meanReactionMs: Double?
    var fastestReactionMs: Double?
    var reactionStdDevMs: Double?
    var score: Int
    var rating: VigilanceRating
}

/// The energy card's copy of a test before #39, synthesized Codable.
private struct LegacyEnergyReactionV1: Codable, Equatable {
    var id: String
    var completedAt: Millis
    var score: Int
    var rating: String
    var sample: Bool
}

@Suite("Reaction Test downgrade and import compatibility")
struct VigilanceCompatibilityTests {
    private var current: VigilanceSession {
        Vigilance.buildSession(
            id: "v2", startedAt: 1_790_000_000_000, completedAt: 1_790_000_030_400,
            trials: [VigilanceTrial(cueAt: 1_790_000_001_500, reactionMs: 286, cueLatencyMs: 9),
                     VigilanceTrial(cueAt: 1_790_000_004_000, reactionMs: nil, cueLatencyMs: 4)],
            falseStarts: [VigilanceFalseStart(at: 1_790_000_000_900)], deviceModel: "iPhone18,1"
        )
    }

    private var earlier: VigilanceSession {
        VigilanceSession(
            id: "v1", startedAt: 1_789_000_000_000, completedAt: 1_789_000_060_000, durationMs: 60_000,
            trialCount: 14, validReactionCount: 13, falseStartCount: 0, lapseCount: 1,
            medianReactionMs: 301, meanReactionMs: 309, fastestReactionMs: 250, reactionStdDevMs: 40,
            score: 64, rating: .steady
        )
    }

    /// What an older build writes back after opening `data` and saving: it
    /// decodes the sessions in its own shape and drops the keys it doesn't know.
    private func reSavedByAnOlderBuild(_ data: Data) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sessions = try JSONSerialization.data(withJSONObject: try #require(object["vigilanceSessions"]))
        let old = try JSONDecoder().decode([LegacyVigilanceSessionV1].self, from: sessions)
        object["vigilanceSessions"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old))
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Loads like StateStore.load: StateStore keeps a `state.corrupt.*` copy
    /// only when decoding fails or `droppingInvalidTimes()` changes the state.
    private func load(_ data: Data) throws -> (state: AppState, wouldKeepCorruptCopy: Bool) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aurora-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try data.write(to: directory.appendingPathComponent(StateMigration.stateFileName))
        let loaded = try #require(try StateMigration.load(directory: directory))
        return (loaded.state, loaded.state.droppingInvalidTimes() != loaded.state)
    }

    @Test func anOlderBuildOpensAFileWithTheCurrentTest() throws {
        var state = AppState()
        state.vigilanceSessions = [current, earlier]
        let data = try StateMigration.encode(state)
        let old = try JSONDecoder().decode([LegacyVigilanceSessionV1].self, from: JSONSerialization.data(
            withJSONObject: try #require((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["vigilanceSessions"])))
        #expect(old.map(\.id) == ["v2", "v1"])
        #expect(old[0].score == current.score && old[0].durationMs == current.durationMs && old[0].trialCount == 2)
    }

    /// A downgrade that saves keeps every summary field and loses what the
    /// older shape has no key for. The session then reads as the earlier test.
    @Test func aFileReSavedByAnOlderBuildKeepsTheSummaryAndLosesTheVersion() throws {
        var state = AppState()
        state.vigilanceSessions = [current, earlier]
        let resaved = try reSavedByAnOlderBuild(StateMigration.encode(state))
        let text = String(decoding: resaved, as: UTF8.self)
        for key in ["protocolVersion", "trials", "falseStarts", "deviceModel"] { #expect(!text.contains("\"\(key)\""), "\(key)") }

        let (loaded, wouldKeepCorruptCopy) = try load(resaved)
        #expect(!wouldKeepCorruptCopy)
        let back = try #require(loaded.vigilanceSessions.first { $0.id == "v2" })
        // Survives: every field the older shape has.
        #expect(back.startedAt == current.startedAt && back.completedAt == current.completedAt && back.durationMs == current.durationMs)
        #expect(back.trialCount == current.trialCount && back.validReactionCount == current.validReactionCount)
        #expect(back.falseStartCount == current.falseStartCount && back.lapseCount == current.lapseCount)
        #expect(back.medianReactionMs == current.medianReactionMs && back.meanReactionMs == current.meanReactionMs)
        #expect(back.fastestReactionMs == current.fastestReactionMs && back.reactionStdDevMs == current.reactionStdDevMs)
        #expect(back.score == current.score && back.rating == current.rating)
        // Lost: the version, trials, false starts and device. It now reads as
        // the earlier 60-second test though it lasted 30 seconds.
        #expect(back.protocolVersion == 1 && back.trials.isEmpty && back.falseStarts.isEmpty && back.deviceModel == nil)
        #expect(back.protocolLabel == "Earlier 60-second test")
        // The earlier test is unchanged.
        #expect(loaded.vigilanceSessions.first { $0.id == "v1" } == earlier)
    }

    /// An unedited file from a build before #39 loads with no copy kept aside.
    @Test func anOlderBuildsFileLoadsWithoutACorruptCopy() throws {
        let file = #"{"schemaVersion":2,"doses":[],"sleeps":[],"vigilanceSessions":[{"id":"v1","startedAt":1789000000000,"completedAt":1789000060000,"durationMs":60000,"trialCount":14,"validReactionCount":13,"falseStartCount":0,"lapseCount":1,"medianReactionMs":301,"meanReactionMs":309,"fastestReactionMs":250,"reactionStdDevMs":40,"score":64,"rating":"Steady"},{"id":"v0","startedAt":1788000000000,"completedAt":1788000060000,"durationMs":60000,"trialCount":12,"validReactionCount":10,"falseStartCount":1,"lapseCount":2,"score":41,"rating":"Slipping"}]}"#
        let (loaded, wouldKeepCorruptCopy) = try load(Data(file.utf8))
        #expect(!wouldKeepCorruptCopy)
        #expect(loaded.vigilanceSessions.map(\.id) == ["v1", "v0"])
        #expect(loaded.vigilanceSessions.allSatisfy { $0.protocolVersion == 1 && $0.trials.isEmpty && $0.protocolLabel == "Earlier 60-second test" })
        #expect(loaded.vigilanceSessions[0] == earlier)
        #expect(loaded.vigilanceSessions[1].medianReactionMs == nil && loaded.vigilanceSessions[1].score == 41)
    }

    @Test func reactNativeImportsAreTheEarlierTest() throws {
        let fixture = try Fixture.load("legacy")
        let now = try #require(fixture.double("now"))
        guard case .object(let cases) = fixture["cases"] ?? .null else {
            Issue.record("missing cases")
            return
        }
        var imported = 0
        for (name, item) in cases {
            let state = try LegacyState.decode(try #require(item.text("raw")), now: now)
            for session in state.vigilanceSessions {
                imported += 1
                #expect(session.protocolVersion == 1, "\(name)")
                #expect(session.protocolLabel == "Earlier 60-second test", "\(name)")
                #expect(session.trials.isEmpty && session.falseStarts.isEmpty && session.deviceModel == nil, "\(name)")
            }
            // And it survives a save and load in this build.
            let back = try StateMigration.decode(StateMigration.encode(state))
            #expect(back.vigilanceSessions == state.vigilanceSessions, "\(name)")
        }
        #expect(imported > 0)
    }

    @Test func aSavedConversationFromBeforeVersionsStillDecodes() throws {
        let now: Millis = 1_791_481_200_000
        let clock = LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        var state = AppState()
        var recent = earlier
        recent.id = "recent"; recent.startedAt = now - 2 * hourMs; recent.completedAt = now - 2 * hourMs + 60_000
        state.vigilanceSessions = [recent]
        let card = AssistantCards.make(.energy, state: state, now: now, clock: clock,
                                       text: .localized(locale: Locale(identifier: "en_US"), timeZone: clock.timeZone))
        #expect(card.energy?.reactions.map(\.protocolVersion) == [1])
        var conversation = ConversationState()
        conversation.messages = [ConversationMessage(text: "How is my energy?", isUser: true), ConversationMessage(text: card.title, card: card)]

        // Remove every reaction's protocolVersion, as a build before #39 wrote it.
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(conversation)) as? [String: Any])
        var messages = try #require(object["messages"] as? [[String: Any]])
        var cardObject = try #require(messages[1]["card"] as? [String: Any])
        var energy = try #require(cardObject["energy"] as? [String: Any])
        var reactions = try #require(energy["reactions"] as? [[String: Any]])
        #expect(reactions.count == 1)
        for index in reactions.indices { reactions[index]["protocolVersion"] = nil }
        energy["reactions"] = reactions; cardObject["energy"] = energy; messages[1]["card"] = cardObject; object["messages"] = messages
        let older = try JSONSerialization.data(withJSONObject: object)
        #expect(!String(decoding: older, as: UTF8.self).contains("protocolVersion"))

        let decoded = try JSONDecoder().decode(ConversationState.self, from: older)
        let reaction = try #require(decoded.messages.last?.card?.energy?.reactions.first)
        #expect(reaction.protocolVersion == nil && reaction.title == "Earlier 60-second test")
        #expect(reaction.id == "recent" && reaction.score == recent.score)
        // And an older build still reads this build's card.
        let current = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try #require(card.energy?.reactions.first)))
        let old = try JSONDecoder().decode(LegacyEnergyReactionV1.self, from: JSONSerialization.data(withJSONObject: current))
        #expect(old.id == "recent" && old.score == recent.score)
    }
}
