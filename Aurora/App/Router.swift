import AuroraCore
import Observation
import SwiftUI

enum HistoryRoute: Hashable {
    case sleep
    case caffeine
}

/// Where the app is: the selected tab, each tab's pushed screens, and the
/// modals. Deep links and signal destinations go through here.
///
/// While the walkthrough runs it locks the router to its step's tab: tab
/// changes, pushes, Settings, the Reaction Test and links from any button or
/// URL are ignored, so nothing can leave the walkthrough except Skip or
/// Finish. The lock is the one place this is enforced; the tab bar, in-screen
/// buttons and modals all go through it.
@MainActor
@Observable
final class Router {
    private(set) var tab: AppTab = .summary
    /// Bound to each tab's NavigationStack, which pops by setting it; pushes
    /// go through `push`.
    var summaryPath: [HistoryRoute] = []
    var sleepPath: [HistoryRoute] = []
    var logPath: [HistoryRoute] = []
    var insightsPath: [HistoryRoute] = []
    private(set) var showSettings = false
    private(set) var showReactionTest = false
    /// The walkthrough step's tab while the walkthrough runs; `nil` otherwise.
    private(set) var walkthroughTab: AppTab?

    var isLocked: Bool { walkthroughTab != nil }

    /// Locks to `tab` for the current walkthrough step, closing anything open.
    func lock(to tab: AppTab) {
        walkthroughTab = tab
        self.tab = tab
        showSettings = false
        showReactionTest = false
        summaryPath = []
        sleepPath = []
        logPath = []
        insightsPath = []
    }

    func unlock() {
        walkthroughTab = nil
    }

    func select(_ tab: AppTab) {
        guard !isLocked else { return }
        self.tab = tab
    }

    func push(_ route: HistoryRoute, on tab: AppTab) {
        guard !isLocked else { return }
        self.tab = tab
        switch tab {
        case .summary: summaryPath.append(route)
        case .sleep: sleepPath.append(route)
        case .log: logPath.append(route)
        case .insights: insightsPath.append(route)
        }
    }

    func presentSettings() {
        guard !isLocked else { return }
        showSettings = true
    }

    func presentReactionTest() {
        guard !isLocked else { return }
        showReactionTest = true
    }

    func dismissSettings() { showSettings = false }
    func dismissReactionTest() { showReactionTest = false }

    func open(_ link: DeepLink) {
        guard !isLocked else { return }
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

/// True while the walkthrough runs, so screens can show their data-changing
/// controls as unavailable. AppModel ignores such changes regardless.
private struct WalkthroughLockedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var walkthroughLocked: Bool {
        get { self[WalkthroughLockedKey.self] }
        set { self[WalkthroughLockedKey.self] = newValue }
    }
}
