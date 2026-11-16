import AppIntents
import AuroraCore

/// The drinks a shortcut can prefill in the review card: the Quick Add
/// presets at their listed amounts, or the person's usual drink. Matcha has
/// no sourced amount, so it is manual entry only.
enum ShortcutDrink: String, AppEnum {
    case usual, espresso, drip, energy

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Drink" }
    static var caseDisplayRepresentations: [ShortcutDrink: DisplayRepresentation] {
        [.usual: "My usual", .espresso: "Espresso", .drip: "Drip", .energy: "Energy drink"]
    }

    var choice: LogDrinkShortcut.Choice { LogDrinkShortcut.Choice(rawValue: rawValue) ?? .usual }
}

/// Opens Aurora's review card prefilled with the chosen drink. Nothing is
/// saved until the person taps Save on the card, which then offers Undo for
/// exactly that entry (v0.1.0 save rule: no background saves).
struct LogDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Drink"
    static let description = IntentDescription("Opens Aurora to review this drink. Nothing is saved until you tap Save.")
    static let openAppWhenRun = true

    @Parameter(title: "Drink", default: .usual)
    var drink: ShortcutDrink

    init() {}
    init(drink: ShortcutDrink) { self.drink = drink }

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$drink)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        CaffeineReviewHandoff.shared.request.request(drink: drink.choice)
        return .result(dialog: "Review your drink in Aurora. Nothing was saved.")
    }
}

struct AuroraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogDrinkIntent(),
            phrases: [
                "Log a drink in \(.applicationName)",
                "Log my usual in \(.applicationName)",
                "Log \(\.$drink) in \(.applicationName)",
                "Log a \(\.$drink) in \(.applicationName)",
            ],
            shortTitle: "Log Drink",
            systemImageName: "cup.and.saucer.fill"
        )
        // Opens the manual entry card instead of saving (#86).
        AppShortcut(
            intent: ReviewCaffeineIntent(),
            phrases: ["Review a drink in \(.applicationName)"],
            shortTitle: "Review Drink",
            systemImageName: "cup.and.saucer"
        )
    }
}
