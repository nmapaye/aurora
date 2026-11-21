import Foundation

/// The interactive drink and sleep impact card opened from a caffeine
/// receipt (owner request, Nov 20): pick what the drink really was, how many
/// shots and cups, when it was had and when bed is, and see how much
/// caffeine is still in the body at bedtime, when it falls under 50 mg, the
/// latest time the same drink would clear that by bed, and a plain sleep
/// impact estimate. Pure math; the view only edits `Input`.
///
/// Figures: espresso about 63 mg per shot, chai tea about 47 mg, brewed
/// coffee about 95 mg per 8 fl oz (USDA). Decay is first order with the
/// person's half-life. The 8.8 hour gap is from Gardiner et al. 2023
/// (Sleep Medicine Reviews, 24 studies, about 107 mg coffee).
public enum DrinkImpact {
    public static let mgPerShot = 63.0
    public static let chaiTeaMg = 47.0
    public static let dripMg = 95.0
    public static let thresholdMg = 50.0
    public static let recommendedGapHours = 8.8
    public static let halfLifeRange: ClosedRange<Double> = 3...8
    public static let fallbackBedMinute = 23 * 60

    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case asLogged, latte, caramelLatte, dirtyChai, americano, drip
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .asLogged: "As Logged"
            case .latte: "Latte"
            case .caramelLatte: "Caramel Latte"
            case .dirtyChai: "Dirty Chai"
            case .americano: "Americano"
            case .drip: "Drip Coffee"
            }
        }
        /// A starting guess from the entry's name; anything else is As Logged.
        public static func guess(from source: String?) -> Kind {
            let name = (source ?? "").lowercased()
            if name.contains("caramel") || name.contains("dolce") { return .caramelLatte }
            if name.contains("chai") { return .dirtyChai }
            if name.contains("americano") { return .americano }
            if name.contains("latte") { return .latte }
            return .asLogged
        }
        /// Whether the shot count changes this drink's caffeine.
        public var usesShots: Bool { self != .asLogged && self != .drip }
        public var note: String {
            switch self {
            case .asLogged: "Uses the amount on your entry."
            case .latte: "A latte’s caffeine comes only from its espresso shots; milk adds none."
            case .caramelLatte: "Caramel adds no caffeine. Each syrup pump is about 20 kcal and 5 g sugar, so figure 15 to 25 g added sugar."
            case .dirtyChai: "Dirty chai adds about 47 mg from the tea on top of the shots."
            case .americano: "An Americano is shots and water, so it matches a latte with the same shots."
            case .drip: "A standard 8 fl oz brewed coffee is about 95 mg (USDA). Shots don’t apply."
            }
        }
    }

    public enum Level: String, Sendable {
        case low = "Low", moderate = "Moderate", high = "High"
        /// Estimated total sleep lost, in minutes.
        public var sleepLoss: ClosedRange<Int> {
            switch self {
            case .low: 0...10
            case .moderate: 15...40
            case .high: 30...60
            }
        }
        public var summary: String {
            switch self {
            case .low: "Little caffeine by bed. Sleep should be close to normal."
            case .moderate: "You’ll likely still fall asleep; expect lighter deep sleep in the first half of the night."
            case .high: "Expect to take longer to fall asleep and lose deep sleep."
            }
        }
    }

    public struct Input: Equatable, Sendable {
        public var kind: Kind
        public var loggedMg: Double
        public var shots: Int
        public var cups: Int
        public var drankAt: Millis
        public var bedtime: Millis
        public var halfLifeHours: Double
        public var dailyLimitMg: Double

        public init(kind: Kind = .asLogged, loggedMg: Double, shots: Int = 2, cups: Int = 1, drankAt: Millis, bedtime: Millis,
                    halfLifeHours: Double, dailyLimitMg: Double = 400) {
            self.kind = kind; self.loggedMg = loggedMg; self.shots = shots; self.cups = cups
            self.drankAt = drankAt; self.bedtime = bedtime; self.halfLifeHours = halfLifeHours; self.dailyLimitMg = dailyLimitMg
        }
    }

    public struct Result: Equatable, Sendable {
        public var perCupMg: Double
        public var totalMg: Double
        public var percentOfLimit: Double
        public var hoursBeforeBed: Double
        public var mgAtBed: Double
        /// When the body falls under 50 mg; nil when the drink starts under it.
        public var underThresholdAt: Millis?
        /// The latest drink time that is under 50 mg by bedtime; nil when
        /// even a drink at bedtime would be under it.
        public var latestTimeForBed: Millis?
        public var level: Level
        /// How far short of the 8.8 hour gap this timing is (0 when clear).
        public var gapShortHours: Double
    }

    public static func perCupMg(_ input: Input) -> Double {
        switch input.kind {
        case .asLogged: input.loggedMg / Double(max(1, input.cups))
        case .drip: dripMg
        case .dirtyChai: Double(input.shots) * mgPerShot + chaiTeaMg
        case .latte, .caramelLatte, .americano: Double(input.shots) * mgPerShot
        }
    }

    public static func remaining(_ mg: Double, afterHours hours: Double, halfLife: Double) -> Double {
        guard hours > 0 else { return mg }
        return mg * pow(0.5, hours / max(0.5, halfLife))
    }

    public static func evaluate(_ input: Input) -> Result {
        let halfLife = min(max(input.halfLifeHours, halfLifeRange.lowerBound), halfLifeRange.upperBound)
        let per = perCupMg(input)
        let total = input.kind == .asLogged ? input.loggedMg : per * Double(max(1, input.cups))
        let gap = max(0, (input.bedtime - input.drankAt) / Double(hourMs))
        let atBed = remaining(total, afterHours: gap, halfLife: halfLife)
        var under: Millis?
        var latest: Millis?
        if total > thresholdMg {
            let hoursToThreshold = halfLife * log2(total / thresholdMg)
            under = input.drankAt + (hoursToThreshold * Double(hourMs)).rounded()
            latest = input.bedtime - (hoursToThreshold * Double(hourMs)).rounded()
        }
        let level: Level = atBed < 25 && gap >= 8 ? .low : atBed < 75 ? .moderate : .high
        return Result(perCupMg: per, totalMg: total, percentOfLimit: input.dailyLimitMg > 0 ? total / input.dailyLimitMg * 100 : 0,
                      hoursBeforeBed: gap, mgAtBed: atBed, underThresholdAt: under, latestTimeForBed: latest,
                      level: level, gapShortHours: max(0, recommendedGapHours - gap))
    }

    /// Points every 30 minutes from the drink to 12 hours later.
    public static func curve(_ input: Input) -> [(t: Millis, mg: Double)] {
        let total = evaluate(input).totalMg
        let halfLife = min(max(input.halfLifeHours, halfLifeRange.lowerBound), halfLifeRange.upperBound)
        return stride(from: 0, through: 24, by: 1).map { step in
            let hours = Double(step) / 2
            return (input.drankAt + hours * Double(hourMs), remaining(total, afterHours: hours, halfLife: halfLife))
        }
    }

    /// Bedtime for the card: the next recent sleep start (at least three
    /// recorded nights) after the drink, else 11:00 PM.
    public static func defaultBedtime(after drankAt: Millis, sleeps: [SleepSession], now: Millis, clock: LocalClock) -> Millis {
        let minute = CaffeineAtTime.recentSleepStart(sleeps, now: now, clock: clock)?.minuteOfDay ?? fallbackBedMinute
        let dayStart = clock.startOfDay(drankAt)
        var bed = dayStart + Double(minute) * Double(minuteMs)
        if bed <= drankAt { bed = clock.addingDays(1, to: dayStart) + Double(minute) * Double(minuteMs) }
        return bed
    }

    /// The card's closing line on timing, with the study it comes from.
    public static func timingLine(_ result: Result, formatTime: (Millis) -> String) -> String {
        let gap = String(format: "%.1f", result.hoursBeforeBed)
        var line = result.gapShortHours > 0
            ? "This is \(gap) h before bed, \(String(format: "%.1f", result.gapShortHours)) h short of the 8.8 h a 2023 review of 24 studies found for a regular coffee."
            : "This is \(gap) h before bed, clear of the 8.8 h a 2023 review of 24 studies found for a regular coffee."
        if let latest = result.latestTimeForBed, result.mgAtBed >= thresholdMg {
            line += " Have it by \(formatTime(latest)) to be under 50 mg at bed."
        }
        let loss = result.level.sleepLoss
        line += " Estimated sleep lost: \(loss.lowerBound == 0 ? "up to \(loss.upperBound)" : "\(loss.lowerBound) to \(loss.upperBound)") minutes, mostly deep sleep."
        return line
    }
}
