import Foundation
import Testing
@testable import AuroraCore

struct CapabilitiesTests {
    @Test func everyPhraseRoutesToItsIntentWithoutAModel() {
        for capability in Capabilities.all {
            #expect(AssistantPlanner.explicitIntent(capability.phrase) == capability.intent, "\(capability.phrase)")
        }
    }

    @Test func everyIntentButUnsupportedHasOneCapability() {
        let covered = Set(Capabilities.all.map(\.intent))
        #expect(covered == Set(AssistantIntent.allCases).subtracting([.unsupported]))
        #expect(covered.count == Capabilities.all.count)
        #expect(Capabilities.tiles.allSatisfy { Capabilities.capability($0) != nil })
    }

    @Test func helpQuestionsOpenTheCapabilities() {
        for text in ["help", "Help", "What can you do?", "what can Aurora do", "What can I ask?", "features", "show me everything"] {
            #expect(AssistantPlanner.explicitIntent(text) == .help, "\(text)")
        }
        // Other requests that merely contain the word stay where they were.
        #expect(AssistantPlanner.explicitIntent("help me log coffee, I had a latte") != .help)
        #expect(AssistantPlanner.explicitIntent("export records") == .exports)
    }

    @Test func typingFindsCapabilitiesByWordStart() {
        #expect(Capabilities.matching("cut").map(\.intent) == [.cutoffScenario])
        #expect(Capabilities.matching("energy cu").map(\.intent) == [.energyProjection])
        #expect(Capabilities.matching("exp").first?.intent == .exports)
        #expect(Capabilities.matching("coffee").first?.intent == .logCaffeine)
        // Title matches rank before keyword-only matches.
        #expect(Capabilities.matching("energy").prefix(2).map(\.intent) == [.energyCheckIn, .explainEnergy])
        #expect(Capabilities.matching("energy").count <= Capabilities.matchLimit)
        #expect(Capabilities.matching("x").isEmpty)
        #expect(Capabilities.matching("   ").isEmpty)
        #expect(Capabilities.matching("zzz qqq").isEmpty)
    }

    func card(_ kind: AssistantCard.Kind, state: AssistantCard.State = .ready, record: String? = nil) -> AssistantCard {
        var card = AssistantCard(kind: kind, capturedAt: 0, title: "")
        card.state = state; card.recordKind = record
        return card
    }

    @Test func followUpsAreTheNaturalNextSteps() {
        let clock = LocalClock(timeZone: TimeZone(identifier: "UTC")!)
        let morning: Millis = 1_791_460_800_000 - 3 * hourMs   // 09:00 UTC
        let afternoon: Millis = 1_791_460_800_000 + 3 * hourMs // 15:00 UTC
        func next(_ card: AssistantCard, _ now: Millis) -> [AssistantIntent] { FollowUps.after(card, now: now, clock: clock).map(\.intent) }
        #expect(next(card(.energy), morning) == [.energyProjection, .energyCheckIn])
        #expect(next(card(.energyProjection), afternoon) == [.cutoffScenario, .energyCheckIn])
        #expect(next(card(.energyProjection), morning) == [.energyCheckIn, .weeklyTrends])
        #expect(next(card(.receipt, state: .saved, record: "caffeine"), morning) == [.energyProjection, .explainEnergy])
        #expect(next(card(.receipt, state: .undone, record: "caffeine"), morning).isEmpty)
        #expect(next(card(.caffeineDraft), morning).isEmpty)
        #expect(next(card(.capabilities), morning).isEmpty)
        // Never more than three, and never the card's own action.
        for kind in AssistantCard.Kind.allCases {
            let follow = FollowUps.after(card(kind, state: .saved, record: "caffeine"), now: afternoon, clock: clock)
            #expect(follow.count <= 3)
            #expect(!follow.contains { $0.intent == card(kind).refreshIntent && kind != .receipt })
        }
    }
}
