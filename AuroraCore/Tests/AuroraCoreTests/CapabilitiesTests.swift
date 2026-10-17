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

    @Test func everydayTilesKeepTheirRequestsAndShortLabels() {
        let tiles = Capabilities.tiles.compactMap(Capabilities.capability)
        // UI tests find these by `assistant-quick-<phrase>`.
        #expect(tiles.map(\.phrase) == ["Morning briefing", "Log caffeine", "How is my energy?", "Reaction test"])
        #expect(tiles.map(\.shortTitle) == ["Briefing", "Caffeine", "Energy", "Reaction"])
        // One caption line in a tile about 84 pt wide, and never an amount or a time.
        for capability in Capabilities.all {
            #expect(!capability.shortTitle.isEmpty && capability.shortTitle.count <= 9, "\(capability.shortTitle)")
            #expect(!capability.shortTitle.contains { $0.isNumber }, "\(capability.shortTitle)")
        }
    }

    @Test func bottomRowIsTheNewestAnswersNextStepsThenTheTiles() {
        let utc = LocalClock(timeZone: TimeZone(identifier: "UTC")!)
        func row(_ card: AssistantCard?, clock: LocalClock = utc) -> [AssistantIntent] { Capabilities.bottomRow(after: card, clock: clock).map(\.id) }
        let tiles = Capabilities.tiles
        #expect(row(nil) == tiles)
        #expect(Capabilities.bottomRow(after: nil, clock: utc).allSatisfy { !$0.isNextStep })
        #expect(row(card(.energy)) == [.energyProjection, .energyCheckIn, .briefing, .logCaffeine])
        #expect(Capabilities.bottomRow(after: card(.energy), clock: utc).map(\.isNextStep) == [true, true, false, false])
        // A next step that is also a tile shows once, as the next step.
        #expect(row(card(.reaction)) == [.weeklyTrends, .explainEnergy, .briefing, .logCaffeine])
        #expect(row(card(.calendar)) == [.briefing, .energyProjection, .logCaffeine, .explainEnergy])
        #expect(Capabilities.bottomRow(after: card(.calendar), clock: utc).map(\.isNextStep) == [true, true, false, false])
        // No next steps: the everyday tiles.
        #expect(row(card(.caffeineDraft)) == tiles)
        #expect(row(card(.receipt, state: .undone, record: "caffeine")) == tiles)
        for kind in AssistantCard.Kind.allCases {
            let intents = row(card(kind, state: .saved, record: "caffeine"))
            #expect(intents.count == 4 && Set(intents).count == 4, "\(kind)")
        }
    }

    /// A new conversation opens on one line and three starting points; the
    /// full list stays one tap away, and the welcome offers no next steps.
    @Test func welcomeOffersThreeStartingPointsIncludingEverything() {
        let utc = LocalClock(timeZone: TimeZone(identifier: "UTC")!)
        let welcome = AssistantCards.make(.welcome, state: AppState(), now: 0, clock: utc, text: .localized(timeZone: utc.timeZone))
        #expect(welcome.title == "Ready when you are." && welcome.summary.isEmpty)
        #expect(welcome.refreshIntent == nil)
        #expect(CopyRules.violations(in: welcome.title).isEmpty)
        let chips = Capabilities.welcome.compactMap(Capabilities.capability)
        #expect(chips.map(\.title) == ["Log caffeine", "Log sleep", "What can you do?"])
        #expect(chips.map { AssistantPlanner.explicitIntent($0.phrase) } == [.logCaffeine, .logSleep, .help])
        #expect(Capabilities.bottomRow(after: welcome, clock: utc).allSatisfy { !$0.isNextStep })
    }

    @Test func bottomRowIsTimedByTheCardNotTheReading() {
        let utc = LocalClock(timeZone: TimeZone(identifier: "UTC")!)
        let pacific = LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        func curve(at capturedAt: Millis) -> AssistantCard {
            var card = AssistantCard(kind: .energyProjection, capturedAt: capturedAt, title: "")
            card.state = .ready
            return card
        }
        let morning: Millis = 1_791_460_800_000 - 3 * hourMs   // 09:00 UTC
        let afternoon: Millis = 1_791_460_800_000 + 3 * hourMs // 15:00 UTC, 08:00 in Los Angeles
        #expect(Capabilities.bottomRow(after: curve(at: afternoon), clock: utc).map(\.id) == [.cutoffScenario, .energyCheckIn, .briefing, .logCaffeine])
        #expect(Capabilities.bottomRow(after: curve(at: morning), clock: utc).map(\.id) == [.energyCheckIn, .weeklyTrends, .briefing, .logCaffeine])
        // The person's own clock decides which part of the day the card is from.
        #expect(Capabilities.bottomRow(after: curve(at: afternoon), clock: pacific).map(\.id) == [.energyCheckIn, .weeklyTrends, .briefing, .logCaffeine])
    }
}
