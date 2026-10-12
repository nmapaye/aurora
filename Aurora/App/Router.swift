import AuroraCore
import Observation
import SwiftUI

enum HistoryRoute: Hashable {
    case sleep
    case caffeine
}

/// Where the app is: the selected tab, each tab's pushed screens, and the
/// modals. Deep links and signal destinations go through here.
@MainActor
@Observable
final class Router {
    var tab: AppTab = .summary
    var summaryPath: [HistoryRoute] = []
    var sleepPath: [HistoryRoute] = []
    var logPath: [HistoryRoute] = []
    var insightsPath: [HistoryRoute] = []
    var showSettings = false
    var showReactionTest = false

    func open(_ link: DeepLink) {
        switch link {
        case .tab(let tab):
            self.tab = tab
        case .reactionTest:
            showReactionTest = true
        case .settings:
            showSettings = true
        case .sleepHistory:
            tab = .sleep
            sleepPath = [.sleep]
        case .caffeineHistory:
            tab = .log
            logPath = [.caffeine]
        }
    }
}
