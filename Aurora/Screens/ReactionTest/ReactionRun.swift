import AuroraCore
import Observation
import QuartzCore
import UIKit

/// The clock and touch handling for one Reaction Test screen.
///
/// Every time is on one millisecond timeline: system uptime (the base of
/// `UITouch.timestamp`, `CADisplayLink` and `ProcessInfo.systemUptime`)
/// shifted to wall-clock milliseconds once per run, so a run can't be
/// stretched by a wall-clock change and stored times read as dates.
///
/// A display link calls `Vigilance.advance` every frame. A due cue is
/// stamped with that frame's `targetTimestamp`, the time the frame being
/// prepared is shown, rather than the scheduled time, so cue latency is at
/// most a frame and is measured on each trial. Touches are stamped at
/// touch-down from the touch's own timestamp.
@MainActor
@Observable
final class ReactionRun {
    /// UI tests pass `-AuroraReactionTestHoldCue`: no cue ever appears and the
    /// run doesn't end on its own, so every touch is an early tap the test
    /// can count, and a diagnostics line shows the counts.
    static let holdsCue = ProcessInfo.processInfo.arguments.contains("-AuroraReactionTestHoldCue")

    private(set) var state = VigilanceTaskState()
    /// Whole seconds left, for the countdown.
    private(set) var secondsLeft = Int(Vigilance.testDurationMs / 1000)
    /// Bumps on each counted false start, to flash the screen.
    private(set) var falseStartFlash = 0
    /// Touch-downs the surface reported, counted or not. UI tests only.
    private(set) var touchCount = 0

    @ObservationIgnored private var offsetMs: Double = 0
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var target: LinkTarget?
    /// The finished state and the time it ended.
    @ObservationIgnored var onComplete: ((VigilanceTaskState, Millis) -> Void)?

    var cueVisible: Bool { state.cueVisible }

    private func millis(uptime: TimeInterval) -> Millis {
        uptime * 1000 + offsetMs
    }

    private var nowMillis: Millis {
        millis(uptime: ProcessInfo.processInfo.systemUptime)
    }

    private func random() -> Double { Double.random(in: 0..<1) }

    func start() {
        stop()
        offsetMs = Date.now.timeIntervalSince1970 * 1000 - ProcessInfo.processInfo.systemUptime * 1000
        touchCount = 0
        set(Vigilance.start(at: nowMillis, randomValue: random()))
        secondsLeft = Int(Vigilance.testDurationMs / 1000)
        let target = LinkTarget(run: self)
        let link = CADisplayLink(target: target, selector: #selector(LinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.target = target
        self.link = link
    }

    /// Stops the clock and forgets the run.
    func discard() {
        stop()
        state = VigilanceTaskState()
    }

    func stop() {
        link?.invalidate()
        link = nil
        target = nil
    }

    func pause() {
        set(Vigilance.pause(state, at: nowMillis))
    }

    func resume() {
        set(Vigilance.resume(state, at: nowMillis, randomValue: random()))
    }

    /// A touch-down on the surface, with `UITouch.timestamp`.
    func touchDown(uptime: TimeInterval) {
        guard state.phase == .running else { return }
        touchCount += 1
        let before = state
        let next = Vigilance.tap(before, at: millis(uptime: uptime), randomValue: random())
        set(next)
        // Feedback follows the stamp, so it can't delay it.
        if next.falseStartCount > before.falseStartCount {
            falseStartFlash += 1
            Haptics.warning()
        } else if next.trials != before.trials || next.feedback != before.feedback {
            Haptics.tap()
        }
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = nowMillis
        let next = Vigilance.advance(state, at: now, cueDrawnAt: millis(uptime: link.targetTimestamp), randomValue: random())
        set(next)
        if !Self.holdsCue, let ends = state.endsAt, state.phase == .running, state.pausedAt == nil {
            let left = max(0, Int((ends - now) / 1000 + 0.999))
            if left != secondsLeft { secondsLeft = left }
        }
        if state.phase == .complete {
            stop()
            onComplete?(state, now)
        }
    }

    /// Assigns only real changes, so per-frame ticks don't redraw the screen.
    private func set(_ next: VigilanceTaskState) {
        var next = next
        if Self.holdsCue, next.phase == .running {
            next.endsAt = .greatestFiniteMagnitude
            if next.nextCueAt != nil { next.nextCueAt = .greatestFiniteMagnitude }
        }
        if next != state { state = next }
    }

    /// The `utsname` machine identifier ("iPhone17,1"); in the simulator,
    /// the simulated device's.
    static var deviceModel: String? {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.isEmpty ? nil : machine
    }
}

/// Holds the run weakly so the display link doesn't keep it alive.
private final class LinkTarget: NSObject {
    weak var run: ReactionRun?

    init(run: ReactionRun) {
        self.run = run
    }

    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated { run?.tick(link) }
    }
}
