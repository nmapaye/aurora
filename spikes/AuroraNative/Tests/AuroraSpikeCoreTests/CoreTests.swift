import Foundation
import Testing
@testable import AuroraSpikeCore

@Suite("Serving estimates")
struct ServingTests {
    let mug = DrinkContainer(id: "mug", name: "Mug", capacityML: 300)
    let tumbler = DrinkContainer(id: "tumbler", name: "Tumbler", capacityML: 473.176473)

    @Test func changingMilkOrContainerPreservesEspressoCaffeine() throws {
        let recipe = DrinkRecipe(id: "latte", name: "Latte", detail: "", basis: .espresso(shots: 2))
        let small = try ServingSnapshot(recipe: recipe, container: mug, consumedML: 300)
        let large = try ServingSnapshot(recipe: recipe, container: tumbler, consumedML: tumbler.capacityML)
        let half = try ServingSnapshot(recipe: recipe, container: tumbler, consumedML: tumbler.capacityML / 2)
        #expect(small.caffeineMG == 120)
        #expect(large.caffeineMG == 120)
        #expect(half.caffeineMG == 60)
    }

    @Test func brewedCoffeeScalesWithVolume() throws {
        let recipe = DrinkRecipe(id: "filter", name: "Filter", detail: "", basis: .concentration(mgPerML: 95.0 / 240, reference: "Reference estimate"))
        let serving = try ServingSnapshot(recipe: recipe, container: mug, consumedML: 120)
        #expect(abs(serving.caffeineMG - 47.5) < 0.00001)
    }

    @Test func matchaDoesNotGainCaffeineWhenAddingMilk() throws {
        let recipe = DrinkRecipe(id: "matcha", name: "Matcha latte", detail: "", basis: .fixedServing(mg: 70, reference: "Reference serving"))
        #expect(try ServingSnapshot(recipe: recipe, container: mug, consumedML: 300).caffeineMG == 70)
        #expect(try ServingSnapshot(recipe: recipe, container: tumbler, consumedML: tumbler.capacityML / 2).caffeineMG == 35)
    }

    @Test func unconfiguredShotsCannotSilentlyLog() {
        let recipe = DrinkRecipe(id: "espresso", name: "Espresso", detail: "", basis: .espresso(shots: nil))
        #expect(throws: ServingError.shotsRequired) {
            try ServingSnapshot(recipe: recipe, container: mug, consumedML: 100)
        }
    }

    @Test(arguments: [0.0, -1, .nan, .infinity, 301])
    func rejectsInvalidVolumes(volume: Double) {
        let recipe = DrinkRecipe(id: "espresso", name: "Espresso", detail: "", basis: .espresso(shots: 1))
        #expect(throws: ServingError.invalidVolume) {
            try ServingSnapshot(recipe: recipe, container: mug, consumedML: volume)
        }
    }

    @Test(arguments: [0, -1, 9])
    func rejectsInvalidShots(shots: Int) {
        let recipe = DrinkRecipe(id: "espresso", name: "Espresso", detail: "", basis: .espresso(shots: shots))
        #expect(throws: ServingError.invalidRecipe) {
            try ServingSnapshot(recipe: recipe, container: mug, consumedML: 300)
        }
    }

    @Test func historyIsFrozenAfterRecipeEdits() throws {
        var recipe = DrinkRecipe(id: "espresso", name: "Espresso", detail: "", basis: .espresso(shots: 1))
        let snapshot = try ServingSnapshot(recipe: recipe, container: mug, consumedML: 300)
        recipe.basis = .espresso(shots: 3)
        #expect(snapshot.caffeineMG == 60)
        #expect(try ServingSnapshot(recipe: recipe, container: mug, consumedML: 300).caffeineMG == 180)
    }

    @Test func unitsRoundTripWithoutChangingStoredVolume() {
        #expect(abs(VolumeUnit.fluidOunces.displayValue(473.176473) - 16) < 0.000001)
        #expect(abs(VolumeUnit.fluidOunces.milliliters(16) - 473.176473) < 0.000001)
    }
}

@Suite("Logging and Undo")
struct UndoTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func dose(_ name: String) throws -> CaffeineDose {
        let recipe = DrinkRecipe(id: name, name: name, detail: "", basis: .espresso(shots: 1))
        let serving = try ServingSnapshot(recipe: recipe, container: .shotGlass, consumedML: 30)
        return CaffeineDose(id: UUID(), timestamp: now, serving: serving, isExample: false)
    }

    @Test func undoPreservesInterveningAdds() throws {
        var history = DoseHistory()
        let first = try dose("first")
        let token = history.log(first, now: now)
        let second = try dose("second")
        _ = history.log(second, now: now.addingTimeInterval(1))
        #expect(history.undo(token, now: now.addingTimeInterval(2)) == .removed)
        #expect(history.doses == [second])
    }

    @Test func undoExpiresAtTenSeconds() throws {
        var history = DoseHistory()
        let token = history.log(try dose("first"), now: now)
        #expect(history.undo(token, now: now.addingTimeInterval(10)) == .expired)
        #expect(history.doses.count == 1)
    }

    @Test func undoDoesNotOverwriteEditedEntry() throws {
        var history = DoseHistory()
        var first = try dose("first")
        let token = history.log(first, now: now)
        first.timestamp = now.addingTimeInterval(60)
        history.replace(first)
        #expect(history.undo(token, now: now.addingTimeInterval(2)) == .conflict)
        #expect(history.doses[0].timestamp == first.timestamp)
    }
}

@Suite("Sleep and caffeine time")
struct TimeTests {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }
    func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    @Test func bedtimeMedianCrossesMidnight() {
        let episodes = ["2026-09-05T03:50:00Z", "2026-09-06T04:10:00Z", "2026-09-07T04:05:00Z"].map {
            SleepEpisode(start: date($0), end: date($0).addingTimeInterval(8 * 3600), isMainSleep: true, isExample: true)
        }
        let suggestion = SleepSuggestions.nextBedtime(episodes: episodes, now: date("2026-09-08T16:00:00Z"), calendar: calendar)
        #expect(suggestion == date("2026-09-09T04:05:00Z"))
    }

    @Test func suggestionNeedsThreeMainEpisodes() {
        let start = date("2026-09-08T03:00:00Z")
        let main = SleepEpisode(start: start, end: start.addingTimeInterval(8 * 3600), isMainSleep: true, isExample: true)
        let second = SleepEpisode(start: start.addingTimeInterval(-86400), end: start.addingTimeInterval(-16 * 3600), isMainSleep: true, isExample: true)
        let nap = SleepEpisode(start: start, end: start.addingTimeInterval(1800), isMainSleep: false, isExample: true)
        #expect(SleepSuggestions.nextBedtime(episodes: [main, second, nap], now: start.addingTimeInterval(12 * 3600), calendar: calendar) == nil)
        #expect(SleepSuggestions.nextBedtime(episodes: [], now: start, calendar: calendar) == nil)
    }

    @Test func suggestionIsNotAnAcceptedSleepPlan() {
        #expect(CaffeineModel.bedtimeResidual(doses: [], plan: nil, halfLifeHours: 5) == nil)
    }

    @Test func nonexistentClockTimeUsesNextValidTime() {
        let episodes = ["2026-03-05T07:30:00Z", "2026-03-06T07:30:00Z", "2026-03-07T07:30:00Z"].map {
            SleepEpisode(start: date($0), end: date($0).addingTimeInterval(8 * 3600), isMainSleep: true, isExample: true)
        }
        let suggestion = SleepSuggestions.nextBedtime(episodes: episodes, now: date("2026-03-08T05:00:00Z"), calendar: calendar)
        #expect(suggestion == date("2026-03-08T07:00:00Z"))
    }

    @Test func exampleRecordsAreExcludedUnlessExplicitlyRequested() throws {
        let now = date("2026-09-08T16:00:00Z")
        let recipe = DrinkRecipe(id: "example", name: "Example", detail: "", basis: .espresso(shots: 1))
        let snapshot = try ServingSnapshot(recipe: recipe, container: .shotGlass, consumedML: 30)
        let dose = CaffeineDose(timestamp: now, serving: snapshot, isExample: true)
        #expect(CaffeineModel.activeMG(doses: [dose], at: now, halfLifeHours: 5) == 0)
        #expect(CaffeineModel.activeMG(doses: [dose], at: now, halfLifeHours: 5, includingExamples: true) == 60)
    }

    @Test func caffeineDecaysAndFutureEntriesAreExcluded() throws {
        let now = date("2026-09-08T16:00:00Z")
        let recipe = DrinkRecipe(id: "coffee", name: "Coffee", detail: "", basis: .fixedServing(mg: 100, reference: "Test"))
        let serving = try ServingSnapshot(recipe: recipe, container: .shotGlass, consumedML: 30)
        let past = CaffeineDose(id: UUID(), timestamp: now.addingTimeInterval(-5 * 3600), serving: serving, isExample: false)
        let future = CaffeineDose(id: UUID(), timestamp: now.addingTimeInterval(1), serving: serving, isExample: false)
        let active = try #require(CaffeineModel.activeMG(doses: [past, future], at: now, halfLifeHours: 5))
        #expect(abs(active - 50) < 0.00001)
        #expect(CaffeineModel.activeMG(doses: [past], at: now, halfLifeHours: 0) == nil)
    }

    @Test func planRejectsPastOrReversedWindow() {
        let now = date("2026-09-08T16:00:00Z")
        #expect(throws: SleepPlanError.invalidWindow) { try SleepPlan(start: now, end: now, acceptedAt: now) }
        #expect(throws: SleepPlanError.invalidWindow) { try SleepPlan(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(3600), acceptedAt: now) }
    }
}
