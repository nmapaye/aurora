import AppIntents
import AuroraCore
import SwiftUI

/// The app model this process loaded at launch. App Intents declared in the
/// app target run inside Aurora's own process (launched in the background
/// when `openAppWhenRun` is false), so a shortcut saves through the same
/// `AppModel` and `state.json` as the app: no App Group, no second writer,
/// and saves stay serialized on the main actor.
@MainActor
enum ShortcutHost {
    static weak var model: AppModel?

    /// The loaded model, or the reason a shortcut can't save.
    static func ready() throws -> AppModel {
        guard let model, model.phase == .ready else { throw ShortcutError.unavailable }
        guard model.state.onboarding.completed else { throw ShortcutError.finishSetup }
        return model
    }
}

enum ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable, finishSetup, notSaved

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable: "Aurora couldn’t open its records. Open Aurora to check."
        case .finishSetup: "Open Aurora to finish setting up first."
        case .notSaved: "Couldn’t save this drink. Your previous records are preserved."
        }
    }
}

/// The drinks a shortcut can log without asking for an amount: the Quick
/// Add presets at their listed amounts, or the person's usual drink.
enum ShortcutDrink: String, AppEnum {
    case usual, espresso, drip, matcha, energy

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Drink" }
    static var caseDisplayRepresentations: [ShortcutDrink: DisplayRepresentation] {
        [.usual: "My usual", .espresso: "Espresso", .drip: "Drip", .matcha: "Matcha", .energy: "Energy drink"]
    }

    var choice: LogDrinkShortcut.Choice { LogDrinkShortcut.Choice(rawValue: rawValue) ?? .usual }
}

/// Saves a drink right away and offers Undo in its result.
struct LogDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Drink"
    static let description = IntentDescription("Saves a drink in Aurora right away. Undo removes it.")
    static let openAppWhenRun = false

    @Parameter(title: "Drink", default: .usual)
    var drink: ShortcutDrink

    init() {}
    init(drink: ShortcutDrink) { self.drink = drink }

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$drink)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let model = try ShortcutHost.ready()
        guard let outcome = model.logFromShortcut(drink.choice) else { throw ShortcutError.notSaved }
        let text = LogDrinkShortcut.savedText(outcome, formatTime: model.text.clockTime)
        let dose: Dose? = switch outcome {
        case .log(let dose), .alreadyLogged(let dose): dose
        case .noUsualDrink: nil
        }
        return .result(dialog: "\(text)", view: LoggedDrinkSnippet(text: text, dose: dose))
    }
}

/// Undo for the exact entry a Log Drink result showed. Hidden from the
/// Shortcuts gallery; it runs from the result's Undo button.
struct UndoLoggedDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo Logged Drink"
    static let description = IntentDescription("Removes the drink a shortcut just logged in Aurora.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Entry")
    var doseID: String
    @Parameter(title: "Logged At")
    var loggedAt: Double

    init() {}
    init(doseID: String, loggedAt: Double) {
        self.doseID = doseID
        self.loggedAt = loggedAt
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try ShortcutHost.ready()
        let removed = model.undoShortcutLog(.init(doseID: doseID, loggedAt: loggedAt))
        return .result(dialog: "\(removed.map(LogDrinkShortcut.undoneText) ?? LogDrinkShortcut.nothingToUndoText)")
    }
}

/// "Undo drink in Aurora": removes the last shortcut log for ten minutes.
struct UndoLastDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo Last Logged Drink"
    static let description = IntentDescription("Removes the drink a shortcut logged in Aurora in the last ten minutes.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try ShortcutHost.ready()
        let removed = model.undoLastShortcutLog()
        return .result(dialog: "\(removed.map(LogDrinkShortcut.undoneText) ?? LogDrinkShortcut.nothingToUndoText)")
    }
}

struct LoggedDrinkSnippet: View {
    let text: String
    let dose: Dose?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let dose {
                Button(intent: UndoLoggedDrinkIntent(doseID: dose.id, loggedAt: dose.timestamp)) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .accessibilityIdentifier("shortcut-undo")
            }
        }
        .padding()
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
        AppShortcut(
            intent: UndoLastDrinkIntent(),
            phrases: [
                "Undo drink in \(.applicationName)",
                "Undo the last drink in \(.applicationName)",
            ],
            shortTitle: "Undo Drink",
            systemImageName: "arrow.uturn.backward"
        )
    }
}
