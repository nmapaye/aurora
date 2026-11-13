import AppIntents
import AuroraCore
import Observation

/// App-process memory only. No URL payload, transcript, App Group or second writer.
@MainActor
@Observable
final class CaffeineReviewHandoff {
    static let shared = CaffeineReviewHandoff()
    var request = CaffeineReviewShortcut()
}

/// Intentionally NOT the historical background-saving LogDrinkIntent.
struct ReviewCaffeineIntent: AppIntent {
    static let title: LocalizedStringResource = "Review Caffeine Entry"
    static let description = IntentDescription("Opens Aurora to review a caffeine entry. Nothing is saved until you tap Save.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        CaffeineReviewHandoff.shared.request.request()
        return .result(dialog: "Review your entry in Aurora. Nothing was saved.")
    }
}

struct AuroraReviewShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReviewCaffeineIntent(),
            phrases: ["Review a drink in \(.applicationName)"],
            shortTitle: "Review Drink",
            systemImageName: "cup.and.saucer"
        )
    }
}
