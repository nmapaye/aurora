import Foundation
import Testing
@testable import AuroraCore

/// The owner's Fellini example (Nov 20): one caramel latte, two shots, at
/// 5:27 PM, bed 11:00 PM, 5 h half-life.
@Suite struct DrinkImpactTests {
    let clock = LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
    var day: Millis { clock.startOfDay(1_800_000_000_000) }
    func at(_ hour: Int, _ minute: Int, nextDay: Bool = false) -> Millis {
        (nextDay ? clock.addingDays(1, to: day) : day) + Double(hour * 60 + minute) * Double(minuteMs)
    }
    var fellini: DrinkImpact.Input {
        .init(kind: .caramelLatte, loggedMg: 14, shots: 2, cups: 1, drankAt: at(17, 27), bedtime: at(23, 0), halfLifeHours: 5)
    }

    @Test func matchesTheWorkedExample() {
        let r = DrinkImpact.evaluate(fellini)
        #expect(r.totalMg == 126 && r.perCupMg == 126)
        #expect(Int(r.mgAtBed.rounded()) == 58)
        #expect(r.level == .moderate)
        #expect(abs(r.underThresholdAt! - at(0, 7, nextDay: true)) < 2 * Double(minuteMs))
        #expect(r.gapShortHours > 3.2 && r.gapShortHours < 3.3)
        var slower = fellini; slower.halfLifeHours = 6
        #expect(Int(DrinkImpact.evaluate(slower).mgAtBed.rounded()) == 66)
    }

    @Test func caramelChangesNothingAndDirtyChaiAddsTea() {
        var latte = fellini; latte.kind = .latte
        var chai = fellini; chai.kind = .dirtyChai
        #expect(DrinkImpact.evaluate(latte).totalMg == DrinkImpact.evaluate(fellini).totalMg)
        #expect(DrinkImpact.evaluate(chai).totalMg == 173)
        var both = fellini; both.cups = 2
        #expect(DrinkImpact.evaluate(both).totalMg == 252 && Int(DrinkImpact.evaluate(both).percentOfLimit.rounded()) == 63)
    }

    @Test func asLoggedUsesTheEntryAndDripIgnoresShots() {
        var logged = fellini; logged.kind = .asLogged; logged.loggedMg = 200
        #expect(DrinkImpact.evaluate(logged).totalMg == 200)
        var drip = fellini; drip.kind = .drip; drip.shots = 4
        #expect(DrinkImpact.evaluate(drip).totalMg == 95)
    }

    @Test func latestTimeLandsUnderFiftyAtBed() throws {
        let r = DrinkImpact.evaluate(fellini)
        let latest = try #require(r.latestTimeForBed)
        var earlier = fellini; earlier.drankAt = latest
        #expect(abs(DrinkImpact.evaluate(earlier).mgAtBed - 50) < 0.5)
        let line = DrinkImpact.timingLine(r) { _ in "4:20 PM" }
        #expect(line.contains("Have it by 4:20 PM") && line.contains("15 to 40 minutes"))
        #expect(CopyRules.violations(in: line).isEmpty)
    }

    @Test func smallEarlyDrinkIsLow() {
        var tea = fellini; tea.kind = .asLogged; tea.loggedMg = 40; tea.drankAt = at(9, 0)
        let r = DrinkImpact.evaluate(tea)
        #expect(r.level == .low && r.underThresholdAt == nil && r.latestTimeForBed == nil)
    }

    @Test func bedtimeDefaultsToElevenAfterTheDrink() {
        #expect(DrinkImpact.defaultBedtime(after: at(17, 27), sleeps: [], now: at(18, 0), clock: clock) == at(23, 0))
        #expect(DrinkImpact.defaultBedtime(after: at(23, 30), sleeps: [], now: at(23, 45), clock: clock) == at(23, 0, nextDay: true))
    }

    @Test func curveStartsAtTheDoseAndFalls() {
        let points = DrinkImpact.curve(fellini)
        #expect(points.count == 25 && points.first?.mg == 126)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.mg > $1.mg })
    }

    @Test func kindGuessFromTheEntryName() {
        #expect(DrinkImpact.Kind.guess(from: "Iced Caramel Latte") == .caramelLatte)
        #expect(DrinkImpact.Kind.guess(from: "Dirty Chai") == .dirtyChai)
        #expect(DrinkImpact.Kind.guess(from: "Coffee, Latte") == .latte)
        #expect(DrinkImpact.Kind.guess(from: "Tea, green, ready-to-drink, sweetened") == .asLogged)
        #expect(DrinkImpact.Kind.guess(from: nil) == .asLogged)
    }
}
