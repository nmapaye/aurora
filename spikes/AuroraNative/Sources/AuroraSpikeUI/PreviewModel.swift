import AuroraSpikeCore
import Foundation
import Observation

struct SavedDrink: Identifiable, Equatable {
    var recipe: DrinkRecipe
    var container: DrinkContainer
    var fraction: Double = 1
    var symbol: String
    var id: String { recipe.id }
    var snapshot: ServingSnapshot? {
        try? ServingSnapshot(recipe: recipe, container: container, consumedML: container.capacityML * fraction)
    }
}

@MainActor @Observable
final class PreviewModel {
    var containers = DrinkContainer.presets
    var drinks: [SavedDrink] = [
        .init(recipe: .init(id: "tumbler", name: "Tumbler coffee", detail: "Your everyday coffee", basis: .espresso(shots: nil)), container: .myTumbler, symbol: "waterbottle.fill"),
        .init(recipe: .init(id: "espresso", name: "Morning espresso", detail: "A small morning ritual", basis: .espresso(shots: nil)), container: .shotGlass, symbol: "cup.and.saucer.fill"),
        .init(recipe: .init(id: "matcha", name: "Matcha latte", detail: "70 mg reference serving", basis: .fixedServing(mg: 70, reference: "70 mg per prepared matcha serving is a reference estimate. Powder and recipes vary; extra milk does not increase caffeine.")), container: .init(id: "mug", name: "Mug", capacityML: 300), symbol: "leaf.fill"),
        .init(recipe: .init(id: "filter", name: "Filter coffee", detail: "95 mg per 240 ml reference", basis: .concentration(mgPerML: 95 / 240.0, reference: "95 mg per 240 ml is an example concentration. Brewing method and strength change the actual amount.")), container: .init(id: "mug", name: "Mug", capacityML: 300), symbol: "mug.fill"),
    ]
    var history: DoseHistory
    var episodes: [SleepEpisode]
    var plan: SleepPlan?
    var unit: VolumeUnit = .milliliters
    var halfLifeHours = 5.0
    var lastUndo: LogUndoToken?
    var showIntake = true
    var showSleep = true
    var notice: String?
    var lastChange = Date.distantPast

    init(now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        episodes = (1...7).compactMap { offset in
            guard let wakeDay = calendar.date(byAdding: .day, value: 1 - offset, to: today),
                  let priorDay = calendar.date(byAdding: .day, value: -1, to: wakeDay),
                  let start = calendar.date(bySettingHour: 23, minute: [5, 20, 10, 45, 0, 25, 15][offset - 1], second: 0, of: priorDay),
                  let end = calendar.date(bySettingHour: 7, minute: [0, 15, 0, 30, 15, 10, 0][offset - 1], second: 0, of: wakeDay), end < now else { return nil }
            return SleepEpisode(start: start, end: end, isMainSleep: true, isExample: true)
        }
        var examples: [CaffeineDose] = []
        for (hour, minute, mg, name) in [(8, 30, 95.0, "Example morning coffee"), (11, 45, 60.0, "Example espresso")] {
            guard var time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) else { continue }
            if time > now { time = calendar.date(byAdding: .day, value: -1, to: time) ?? time }
            let recipe = DrinkRecipe(id: "example-\(hour)", name: name, detail: "Example data", basis: .fixedServing(mg: mg, reference: "Example data"))
            if let snapshot = try? ServingSnapshot(recipe: recipe, container: .init(id: "example", name: "Example cup", capacityML: 240), consumedML: 240) {
                examples.append(.init(timestamp: time, serving: snapshot, isExample: true))
            }
        }
        history = DoseHistory(doses: examples)
    }

    var favorites: [SavedDrink] { Array(drinks.prefix(2)) }

    func update(_ drink: SavedDrink) {
        guard let index = drinks.firstIndex(where: { $0.id == drink.id }) else { return }
        if let containerIndex = containers.firstIndex(where: { $0.id == drink.container.id }) {
            containers[containerIndex] = drink.container
        } else {
            containers.append(drink.container)
        }
        for sharedIndex in drinks.indices where drinks[sharedIndex].container.id == drink.container.id {
            drinks[sharedIndex].container = drink.container
        }
        drinks[index] = drink
    }

    func log(_ drink: SavedDrink, now: Date = Date()) {
        do {
            let snapshot = try ServingSnapshot(recipe: drink.recipe, container: drink.container, consumedML: drink.container.capacityML * drink.fraction)
            lastUndo = history.log(.init(timestamp: now, serving: snapshot), now: now)
            lastChange = now
            notice = nil
        } catch { notice = error.localizedDescription }
    }

    func undo(now: Date) {
        guard let token = lastUndo else { return }
        switch history.undo(token, now: now) {
        case .removed: notice = nil
        case .expired: notice = "Undo expired. This entry remains in the preview timeline."
        case .conflict: notice = "That entry changed after logging, so Undo kept the newer version."
        case .missing: notice = nil
        }
        lastUndo = nil
        lastChange = now
    }

    func active(at time: Date) -> Double {
        CaffeineModel.activeMG(doses: history.doses, at: time, halfLifeHours: halfLifeHours, includingExamples: true) ?? 0
    }

    func acceptedPlan(at now: Date) -> SleepPlan? {
        guard let plan, plan.start > now else { return nil }
        return plan
    }

    func intake(at now: Date, calendar: Calendar = .current) -> Double? {
        let today = history.doses.filter { calendar.isDate($0.timestamp, inSameDayAs: now) && $0.timestamp <= now }
        return today.isEmpty ? nil : today.reduce(0) { $0 + $1.serving.caffeineMG }
    }

    func volume(_ ml: Double) -> String {
        let value = unit.displayValue(ml)
        let amount = unit == .milliliters ? value.formatted(.number.precision(.fractionLength(0))) : value.formatted(.number.precision(.fractionLength(0...1)))
        return "\(amount) \(unit.symbol)"
    }
}
