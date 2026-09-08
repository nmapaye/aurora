import Foundation

public struct DrinkContainer: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var capacityML: Double

    public init(id: String, name: String, capacityML: Double) {
        self.id = id
        self.name = name
        self.capacityML = capacityML
    }

    public static let shotGlass = DrinkContainer(id: "shot", name: "Shot glass", capacityML: 30)
    public static let myTumbler = DrinkContainer(id: "my-tumbler", name: "My Tumbler", capacityML: 473.176473)
    public static let presets: [DrinkContainer] = [
        .myTumbler,
        .init(id: "small", name: "Small", capacityML: 240),
        .init(id: "medium", name: "Medium", capacityML: 350),
        .init(id: "large", name: "Large", capacityML: 475),
        .init(id: "mug", name: "Mug", capacityML: 300),
        .init(id: "tumbler", name: "Tumbler", capacityML: 475),
        .shotGlass,
    ]
}

public enum VolumeUnit: String, CaseIterable, Identifiable, Sendable {
    case milliliters, fluidOunces
    public var id: String { rawValue }
    public var symbol: String { self == .milliliters ? "ml" : "US fl oz" }
    public func displayValue(_ ml: Double) -> Double { self == .milliliters ? ml : ml / 29.5735295625 }
    public func milliliters(_ value: Double) -> Double { self == .milliliters ? value : value * 29.5735295625 }
}

public enum CaffeineBasis: Equatable, Codable, Sendable {
    case espresso(shots: Int?)
    case fixedServing(mg: Double, reference: String)
    case concentration(mgPerML: Double, reference: String)

    public var needsShotChoice: Bool {
        if case .espresso(shots: nil) = self { return true }
        return false
    }

    public var explanation: String {
        switch self {
        case .espresso(let shots):
            guard let shots else { return "Choose your usual shots. Reference estimate: 60 mg per shot." }
            return "\(shots) \(shots == 1 ? "shot" : "shots") × 60 mg per shot. Reference estimate; actual coffee varies."
        case .fixedServing(_, let reference), .concentration(_, let reference):
            return reference
        }
    }
}

public struct DrinkRecipe: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public var name: String
    public var detail: String
    public var basis: CaffeineBasis

    public init(id: String, name: String, detail: String, basis: CaffeineBasis) {
        self.id = id
        self.name = name
        self.detail = detail
        self.basis = basis
    }
}

public enum ServingError: Error, Equatable, LocalizedError {
    case invalidVolume, invalidRecipe, shotsRequired
    public var errorDescription: String? {
        switch self {
        case .invalidVolume: "Choose an amount greater than zero and no larger than the container."
        case .invalidRecipe: "Use a valid caffeine estimate and between one and eight espresso shots."
        case .shotsRequired: "Choose your usual espresso shots before logging."
        }
    }
}

/// A value snapshot. Later recipe/container changes cannot change previously logged caffeine.
public struct ServingSnapshot: Equatable, Codable, Sendable {
    public let recipeID: String
    public let drinkName: String
    public let containerName: String
    public let preparedVolumeML: Double
    public let consumedVolumeML: Double
    public let caffeineMG: Double
    public let basis: CaffeineBasis
    public var fraction: Double { consumedVolumeML / preparedVolumeML }

    public init(recipe: DrinkRecipe, container: DrinkContainer, consumedML: Double) throws {
        guard container.capacityML.isFinite, container.capacityML > 0, container.capacityML <= 5_000,
              consumedML.isFinite, consumedML > 0, consumedML <= container.capacityML else {
            throw ServingError.invalidVolume
        }
        let fullMG: Double
        switch recipe.basis {
        case .espresso(let shots):
            guard let shots else { throw ServingError.shotsRequired }
            guard (1...8).contains(shots) else { throw ServingError.invalidRecipe }
            fullMG = Double(shots) * 60
        case .fixedServing(let mg, _):
            fullMG = mg
        case .concentration(let mgPerML, _):
            guard mgPerML.isFinite, mgPerML > 0 else { throw ServingError.invalidRecipe }
            fullMG = mgPerML * container.capacityML
        }
        guard fullMG.isFinite, fullMG > 0, fullMG <= 2_000 else { throw ServingError.invalidRecipe }
        recipeID = recipe.id
        drinkName = recipe.name
        containerName = container.name
        preparedVolumeML = container.capacityML
        consumedVolumeML = consumedML
        caffeineMG = fullMG * (consumedML / container.capacityML)
        basis = recipe.basis
    }
}

public struct CaffeineDose: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var timestamp: Date
    public var serving: ServingSnapshot
    public let isExample: Bool

    public init(id: UUID = UUID(), timestamp: Date, serving: ServingSnapshot, isExample: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.serving = serving
        self.isExample = isExample
    }
}

public struct LogUndoToken: Equatable, Sendable {
    public let dose: CaffeineDose
    public let expiresAt: Date
}

public enum UndoResult: Equatable, Sendable { case removed, expired, conflict, missing }

public struct DoseHistory: Sendable {
    public private(set) var doses: [CaffeineDose]
    public init(doses: [CaffeineDose] = []) { self.doses = doses }

    @discardableResult
    public mutating func log(_ dose: CaffeineDose, now: Date) -> LogUndoToken {
        if !doses.contains(where: { $0.id == dose.id }) { doses.append(dose) }
        return LogUndoToken(dose: dose, expiresAt: now.addingTimeInterval(10))
    }

    public mutating func replace(_ dose: CaffeineDose) {
        guard let index = doses.firstIndex(where: { $0.id == dose.id }) else { return }
        doses[index] = dose
    }

    public mutating func undo(_ token: LogUndoToken, now: Date) -> UndoResult {
        guard now < token.expiresAt else { return .expired }
        guard let index = doses.firstIndex(where: { $0.id == token.dose.id }) else { return .missing }
        guard doses[index] == token.dose else { return .conflict }
        doses.remove(at: index)
        return .removed
    }
}

public struct SleepEpisode: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let isMainSleep: Bool
    public let isExample: Bool

    public init(id: UUID = UUID(), start: Date, end: Date, isMainSleep: Bool, isExample: Bool) {
        self.id = id
        self.start = start
        self.end = end
        self.isMainSleep = isMainSleep
        self.isExample = isExample
    }
}

public enum SleepPlanError: Error, Equatable, LocalizedError {
    case invalidWindow
    public var errorDescription: String? { "Choose a future bedtime and a wake time after it, within 24 hours." }
}

public struct SleepPlan: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let acceptedAt: Date

    public init(start: Date, end: Date, acceptedAt: Date) throws {
        guard start > acceptedAt, end > start, end.timeIntervalSince(start) <= 24 * 3600 else {
            throw SleepPlanError.invalidWindow
        }
        self.start = start
        self.end = end
        self.acceptedAt = acceptedAt
    }
}

public enum SleepSuggestions {
    /// Circular L1 median of the latest seven completed main episodes. Naps are excluded.
    /// Calendar matching handles midnight and nonexistent/repeated local clock times.
    public static func nextBedtime(episodes: [SleepEpisode], now: Date, calendar: Calendar) -> Date? {
        let recent = episodes.filter { $0.isMainSleep && $0.end > $0.start && $0.end <= now }
            .sorted { $0.start > $1.start }.prefix(7)
        guard recent.count >= 3 else { return nil }
        let minutes = recent.map { episode in
            calendar.component(.hour, from: episode.start) * 60 + calendar.component(.minute, from: episode.start)
        }
        func cost(_ candidate: Int) -> Int {
            minutes.reduce(0) { sum, minute in
                let difference = abs(candidate - minute)
                return sum + min(difference, 1_440 - difference)
            }
        }
        // Prefer the most recent observation when several medians have the same cost.
        guard let median = minutes.enumerated().min(by: {
            let left = cost($0.element), right = cost($1.element)
            return left == right ? $0.offset < $1.offset : left < right
        })?.element else { return nil }
        return calendar.nextDate(after: now, matching: DateComponents(hour: median / 60, minute: median % 60), matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }
}

public enum CaffeineModel {
    /// First-order half-life estimate. No absorption delay or individual calibration is modeled.
    public static func activeMG(doses: [CaffeineDose], at date: Date, halfLifeHours: Double, includingExamples: Bool = false) -> Double? {
        guard halfLifeHours.isFinite, halfLifeHours > 0 else { return nil }
        return doses.reduce(0) { total, dose in
            guard dose.timestamp <= date, includingExamples || !dose.isExample else { return total }
            let elapsedHours = date.timeIntervalSince(dose.timestamp) / 3600
            return total + dose.serving.caffeineMG * pow(0.5, elapsedHours / halfLifeHours)
        }
    }

    public static func bedtimeResidual(doses: [CaffeineDose], plan: SleepPlan?, halfLifeHours: Double, includingExamples: Bool = false) -> Double? {
        guard let plan else { return nil }
        return activeMG(doses: doses, at: plan.start, halfLifeHours: halfLifeHours, includingExamples: includingExamples)
    }
}
