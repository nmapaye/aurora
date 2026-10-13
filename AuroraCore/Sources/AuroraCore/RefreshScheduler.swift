import Foundation

/// Why a refresh was asked for.
public enum RefreshTrigger: Hashable, Sendable {
    /// Aurora became active.
    case foreground
    /// iOS granted a background refresh opportunity.
    case background
    /// Health reported a change to a kind Aurora reads.
    case healthChange(HealthDataKind)
    /// The person tapped Refresh, or just turned a Health choice on.
    case explicit
}

/// What one refresh does, decided from its triggers and how fresh each part
/// already is. Health changes refresh only the changed kind. Calendars and
/// suggestions follow foreground, background or explicit requests, never a
/// Health notification, so Health activity can't start reasoning or
/// suggestions by itself.
public enum RefreshPolicy {
    public enum Step: String, CaseIterable, Sendable {
        case healthSleep
        case healthCaffeine
        case calendars
        case suggestions
    }

    /// Foreground and background requests skip a part refreshed this recently.
    public static let minimumInterval: Millis = 15 * minuteMs

    public static func steps(for triggers: Set<RefreshTrigger>, lastRun: [Step: Millis], now: Millis) -> [Step] {
        let opportunity = triggers.contains(.foreground) || triggers.contains(.background)
        let explicit = triggers.contains(.explicit)
        func due(_ step: Step) -> Bool {
            guard let last = lastRun[step] else { return true }
            return now - last >= minimumInterval || now < last
        }
        return Step.allCases.filter { step in
            switch step {
            case .healthSleep:
                explicit || triggers.contains(.healthChange(.sleepAnalysis)) || (opportunity && due(step))
            case .healthCaffeine:
                explicit || triggers.contains(.healthChange(.caffeine)) || (opportunity && due(step))
            case .calendars:
                explicit || (opportunity && due(step))
            case .suggestions:
                // Delivery limits, quiet hours and dismissals apply inside.
                opportunity
            }
        }
    }
}

/// The one refresh path for foreground, background and Health change
/// notifications. A request while a refresh runs joins one follow-up run
/// that covers everything asked for meanwhile, so a burst of notifications
/// costs at most one more run. Runs per activation are bounded.
/// `invalidate()` (erase, disconnect) cancels the work, drops what was
/// queued, and makes late results stale.
@MainActor
public final class RefreshScheduler {
    public typealias Work = @MainActor (_ triggers: Set<RefreshTrigger>, _ isCurrent: @escaping @MainActor () -> Bool) async -> Void

    /// One run plus one follow-up per activation.
    public static let maximumRunsPerActivation = 2

    public private(set) var generation = 0
    public private(set) var runCount = 0
    public var isRunning: Bool { running != nil }

    private let work: Work
    private var queued: Set<RefreshTrigger> = []
    private var running: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(work: @escaping Work) {
        self.work = work
    }

    /// Returns once a run that started after this request finished, or the
    /// scheduler was invalidated.
    public func request(_ trigger: RefreshTrigger) async {
        queued.insert(trigger)
        if running == nil { start() }
        await withCheckedContinuation { waiters.append($0) }
    }

    public func invalidate() {
        generation += 1
        running?.cancel()
        running = nil
        queued = []
        resumeWaiters()
    }

    private func start() {
        let started = generation
        running = Task { @MainActor [weak self] in
            var runs = 0
            while let self, started == self.generation, !self.queued.isEmpty, runs < Self.maximumRunsPerActivation {
                let batch = self.queued
                self.queued = []
                runs += 1
                self.runCount += 1
                await self.work(batch) { [weak self] in self?.generation == started && !Task.isCancelled }
            }
            guard let self, started == self.generation else { return }
            // Requests after the last allowed run are dropped, not looped on.
            // Anchored reads pick up those changes at the next trigger.
            self.queued = []
            self.running = nil
            self.resumeWaiters()
        }
    }

    private func resumeWaiters() {
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }
}
