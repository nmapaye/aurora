import Foundation
import Testing
@testable import AuroraCore

/// "How much caffeine does beer have?" (owner's iPhone, Nov 21) got the
/// generic "What would you like to do?" menu: no code path answered a
/// question about a drink's caffeine. It is now answered from the bundled
/// database only; unlisted drinks get a plain "no entry" line.
@Suite struct CaffeineContentQuestionTests {
    typealias Q = CaffeineContentQuestion
    var db: CaffeineDatabase { CaffeineDatabase.bundled! }

    @Test func beerGetsAPlainNoEntryLineNotTheMenu() throws {
        let answer = try #require(Q.answer("How much caffeine does beer have", db: db))
        #expect(answer == .notInDatabase(drink: "beer"))
        #expect(answer.message == "Aurora’s caffeine database has no entry for beer, so there’s no caffeine amount to show.")
    }

    @Test func rootBeerRecordsDontAnswerForBeer() {
        #expect(Q.answer("Does beer have caffeine?", db: db) == .notInDatabase(drink: "beer"))
        #expect(Q.answer("Is there caffeine in beer", db: db) == .notInDatabase(drink: "beer"))
    }

    @Test func genericDrinksUseTheirUSDARecordAtOneCup() throws {
        let latte = try #require(Q.answer("How much caffeine is in a latte?", db: db))
        #expect(latte == .found(drink: "latte", mg: 86, serving: "1 cup (8 fl oz)", source: "USDA · FDC 2710386"))
        #expect(latte.message == "Latte: 86 mg of caffeine per 1 cup (8 fl oz). Source: USDA · FDC 2710386.")
        #expect(Q.answer("does black tea have caffeine", db: db)
                == .found(drink: "black tea", mg: 47, serving: "1 cup (8 fl oz)", source: "USDA · FDC 173227"))
        #expect(Q.answer("What's the caffeine content of a cup of coffee?", db: db)
                == .found(drink: "coffee", mg: 95, serving: "1 cup (8 fl oz)", source: "USDA · FDC 171890"))
    }

    @Test func aBrandWithSeveralRecordsAsksForTheExactProduct() {
        #expect(Q.answer("Is there caffeine in Red Bull?", db: db) == .several(drink: "red bull"))
    }

    @Test func questionsAboutThePersonATimeOrAnAmountAreNotContentQuestions() {
        for text in [
            "how much caffeine do I have left",
            "how much caffeine did I have at 3pm",
            "how much caffeine will I have at 10pm if I drink coffee at 3",
            "how much caffeine is in my body",
            "how much caffeine is in 2 lattes",
            "how much caffeine should I have",
            "I had a latte",
            "log coffee",
            "what can you do",
        ] {
            #expect(Q.drink(in: text) == nil, "\(text)")
        }
    }

    @Test func answerLinesPassCopyRules() {
        let lines = [
            Q.Answer.found(drink: "latte", mg: 86, serving: "1 cup (8 fl oz)", source: "USDA · FDC 2710386").message,
            Q.Answer.several(drink: "red bull").message,
            Q.Answer.notInDatabase(drink: "beer").message,
        ]
        for line in lines { #expect(CopyRules.violations(in: line).isEmpty, "\(line)") }
    }

    @Test func theTimeQuestionRouteStillTakesItsQuestions() {
        // The app asks CaffeineQuestion first; this one stays a time question.
        #expect(CaffeineQuestion.route("how much caffeine will I have at 10pm if I drink 95 mg at 3pm") != nil)
        #expect(CaffeineQuestion.route("How much caffeine does beer have") == nil)
    }
}
