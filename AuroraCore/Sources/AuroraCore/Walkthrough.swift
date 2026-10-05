import Foundation

public enum AppTab: String, Sendable, CaseIterable, Hashable {
    case summary = "Summary"
    case sleep = "Sleep"
    case log = "Log"
    case insights = "Insights"

    /// SF Symbols for the tab bar: idle, then selected.
    public var symbols: (idle: String, selected: String) {
        switch self {
        case .summary: return ("gauge.with.dots.needle.67percent", "gauge.with.dots.needle.67percent")
        case .sleep: return ("moon", "moon.fill")
        case .log: return ("plus.circle", "plus.circle.fill")
        case .insights: return ("chart.bar", "chart.bar.fill")
        }
    }
}

/// The ten-step first-run walkthrough. While it is pending, tab selection is
/// locked and every deep link goes to the tab that owns the current step.
public enum Walkthrough {
    public struct Step: Equatable, Sendable {
        public var id: String
        public var tab: AppTab
        public var progress: String
        public var title: String
        public var body: String
        /// The content this step reveals.
        public var revealGroups: [String]
        /// What the coach card points at.
        public var anchor: String
        public var isLast: Bool
    }

    public static let startDelayMs: Millis = 300
    public static let scrollSettleMs: Millis = 350
    public static let revealSettleMs: Millis = 900
    public static let reducedMotionSettleMs: Millis = 120
    public static let topClearance: Double = 24

    public static let steps: [Step] = [
        Step(id: "summary-orientation", tab: .summary, progress: "1 of 10", title: "Your day at a glance",
             body: "Estimated alertness and today’s caffeine curve, built from what you record.",
             revealGroups: ["summary-header", "summary-today", "summary-alert"], anchor: "summary-top", isLast: false),
        Step(id: "summary-signals", tab: .summary, progress: "2 of 10", title: "Your pinned signals",
             body: "Caffeine logged today, your latest sleep, and your latest Reaction Test, each with its date and source.",
             revealGroups: ["summary-pinned"], anchor: "summary-pinned", isLast: false),
        Step(id: "summary-logging", tab: .summary, progress: "3 of 10", title: "Log caffeine",
             body: "Caffeine Logged opens Log, where you record the amount, time, and source and see recent entries.",
             revealGroups: [], anchor: "summary-caffeine", isLast: false),
        Step(id: "summary-sleep", tab: .summary, progress: "4 of 10", title: "Next: your sleep",
             body: "Sleep comes from Health or your own entries. The Sleep tab shows each night and where it came from.",
             revealGroups: [], anchor: "summary-sleep", isLast: false),
        Step(id: "sleep-understanding", tab: .sleep, progress: "5 of 10", title: "Your recorded nights",
             body: "Week or Month shows each night you recorded. Tap or drag the chart to read a day; Most Recent Sleep shows its date and source.",
             revealGroups: ["sleep-header", "sleep-history"], anchor: "sleep-top", isLast: false),
        Step(id: "sleep-add-or-connect", tab: .sleep, progress: "6 of 10", title: "Where your sleep comes from",
             body: "Sleep Data holds read-only Health access, manual entries, Sample Data, and every recorded night.",
             revealGroups: ["sleep-data"], anchor: "sleep-data", isLast: false),
        Step(id: "log-quick-add", tab: .log, progress: "7 of 10", title: "Log caffeine",
             body: "Logged Today totals what you record. Tap a drink to log it now, with Undo right after, or use Custom Entry to set the amount and time.",
             revealGroups: ["log-header", "log-quick-add"], anchor: "log-top", isLast: false),
        Step(id: "log-details", tab: .log, progress: "8 of 10", title: "Fix a mistake",
             body: "Recent shows each entry’s date, time, amount, and source. Tap one to edit or delete it; Show All Caffeine Data holds the full history.",
             revealGroups: ["log-details"], anchor: "log-details", isLast: false),
        Step(id: "insights-patterns", tab: .insights, progress: "9 of 10", title: "Your caffeine over time",
             body: "Choose W, 2W, or M. Tap or drag the chart to read a day; days without entries read as no record, not zero.",
             revealGroups: ["insights-header", "insights-range"], anchor: "insights-top", isLast: false),
        Step(id: "insights-learning", tab: .insights, progress: "10 of 10", title: "Your Reaction Test",
             body: "Your latest test shows its date and source. A baseline appears only after 3 tests; Details holds time of day, drinks, and every entry.",
             revealGroups: ["insights-reaction"], anchor: "insights-reaction", isLast: true),
    ]

    public static func clampStep(_ step: Int) -> Int {
        clamp(step, 0, steps.count - 1)
    }

    public static func step(_ index: Int) -> Step {
        steps[clampStep(index)]
    }

    public static func tab(forStep index: Int) -> AppTab {
        step(index).tab
    }

    /// Everything revealed so far on the current step's tab.
    public static func revealedGroups(step index: Int) -> [String] {
        let current = clampStep(index)
        let tab = steps[current].tab
        let first = steps.firstIndex { $0.tab == tab } ?? current
        var groups: [String] = []
        for group in steps[first...current].flatMap(\.revealGroups) where !groups.contains(group) {
            groups.append(group)
        }
        return groups
    }

    public enum Phase: Equatable, Sendable {
        case waiting
        case positioning
        case revealing
        case coaching
        case complete
    }

    public struct State: Equatable, Sendable {
        public var stepIndex: Int
        public var phase: Phase

        public init(stepIndex: Int = 0, phase: Phase = .waiting) {
            self.stepIndex = stepIndex
            self.phase = phase
        }
    }

    public enum Event: Equatable, Sendable {
        case start
        case sync(stepIndex: Int)
        case positioned
        case settled
        case geometryChanged
        case next
        case skip
        case finish
    }

    public static func reduce(_ state: State, _ event: Event) -> State {
        switch event {
        case .sync(let index):
            let phase: Phase = state.phase == .complete ? .complete : state.phase == .waiting ? .waiting : .positioning
            return State(stepIndex: clampStep(index), phase: phase)
        case .start:
            return state.phase == .waiting ? State(stepIndex: clampStep(state.stepIndex), phase: .positioning) : state
        case .positioned:
            return state.phase == .positioning ? State(stepIndex: state.stepIndex, phase: .revealing) : state
        case .settled:
            return state.phase == .revealing ? State(stepIndex: state.stepIndex, phase: .coaching) : state
        case .geometryChanged:
            return state.phase == .revealing || state.phase == .coaching ? State(stepIndex: state.stepIndex, phase: .positioning) : state
        case .next:
            return state.phase == .coaching && state.stepIndex < steps.count - 1
                ? State(stepIndex: state.stepIndex + 1, phase: .positioning)
                : state
        case .skip:
            return state.phase == .complete ? state : State(stepIndex: state.stepIndex, phase: .complete)
        case .finish:
            return state.phase == .coaching && state.stepIndex == steps.count - 1
                ? State(stepIndex: state.stepIndex, phase: .complete)
                : state
        }
    }
}

/// `aurora://` links. Query strings and fragments are ignored.
public enum DeepLink: Equatable, Sendable {
    case tab(AppTab)
    case reactionTest
    case settings
    case sleepHistory
    case caffeineHistory

    public static let schemes: Set<String> = ["aurora", "com.nmapaye.aurora"]

    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), Self.schemes.contains(scheme) else { return nil }
        // aurora://sleep/history parses as host "sleep" and path "/history".
        let parts = ([url.host ?? ""] + url.path.split(separator: "/").map(String.init)).filter { !$0.isEmpty }
        self.init(path: parts.joined(separator: "/"))
    }

    public init?(path: String) {
        var trimmed = path
        if let cut = trimmed.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            trimmed = String(trimmed[..<cut])
        }
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch trimmed {
        case "summary": self = .tab(.summary)
        case "sleep": self = .tab(.sleep)
        case "log": self = .tab(.log)
        case "insights": self = .tab(.insights)
        case "vigilance": self = .reactionTest
        case "settings": self = .settings
        case "sleep/history": self = .sleepHistory
        case "caffeine/history": self = .caffeineHistory
        default: return nil
        }
    }

    /// While the walkthrough is pending, every link goes to the tab that owns
    /// the current step.
    public func resolved(walkthroughPending: Bool, step: Int) -> DeepLink {
        walkthroughPending ? .tab(Walkthrough.tab(forStep: step)) : self
    }
}
