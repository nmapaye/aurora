import Foundation
import Testing
@testable import AuroraCore

/// "How much caffeine does beer have?" (owner's iPhone, Nov 21) got the
/// generic "What would you like to do?" menu: no code path answered a
/// question about a drink's caffeine. It is now answered in code: everyday
/// drinks with no caffeine get "about 0 mg", the rest come from the bundled
/// database, and drinks it can't place get a plain "no entry" line.
@Suite struct CaffeineContentQuestionTests {
    typealias Q = CaffeineContentQuestion
    var db: CaffeineDatabase { CaffeineDatabase.bundled! }

    @Test func beerIsAboutZeroMgNotTheMenu() throws {
        let answer = try #require(Q.answer("How much caffeine does beer have", db: db))
        #expect(answer == .noCaffeine(drink: "beer"))
        #expect(answer.message == "Beer: about 0 mg of caffeine. It isn’t a caffeinated drink, so Aurora’s caffeine database doesn’t list it.")
        #expect(Q.answer("Does beer have caffeine?", db: db) == .noCaffeine(drink: "beer"))
        #expect(Q.answer("Is there caffeine in a beer", db: db) == .noCaffeine(drink: "beer"))
        #expect(Q.answer("how much caffeine do beers have", db: db) == .noCaffeine(drink: "beer"))
    }

    @Test func otherEverydayCaffeineFreeDrinksAreAboutZero() {
        #expect(Q.answer("Does wine have caffeine?", db: db) == .noCaffeine(drink: "wine"))
        #expect(Q.answer("how much caffeine is in a glass of milk", db: db) == .noCaffeine(drink: "milk"))
        #expect(Q.answer("Is there caffeine in orange juice", db: db) == .noCaffeine(drink: "orange juice"))
        #expect(Q.answer("does 7up have caffeine", db: db) == .noCaffeine(drink: "7up"))
        #expect(Q.answer("Does Sprite have caffeine?", db: db) == .noCaffeine(drink: "sprite"))
    }

    @Test func onlyTheWholePhraseCountsAsCaffeineFree() {
        // Drinks that contain a listed word but can have caffeine.
        #expect(Q.answer("how much caffeine is in coffee stout", db: db) != .noCaffeine(drink: "coffee stout"))
        #expect(Q.answer("does chocolate milk have caffeine", db: db) != .noCaffeine(drink: "chocolate milk"))
        #expect(Q.answer("does root beer have caffeine", db: db) != .noCaffeine(drink: "root beer"))
    }

    @Test func aDrinkItCantPlaceStillGetsNoEntry() {
        #expect(Q.answer("how much caffeine is in kvass", db: db) == .notInDatabase(drink: "kvass"))
        #expect(Q.Answer.notInDatabase(drink: "kvass").message
                == "Aurora’s caffeine database has no entry for kvass, so there’s no caffeine amount to show.")
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
            Q.Answer.noCaffeine(drink: "beer").message,
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
