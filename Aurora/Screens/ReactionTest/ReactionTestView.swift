import AuroraCore
import SwiftUI

/// The 60-second Reaction Test. One timer aims at the next event (cue due,
/// response window over, countdown second, end of test), so a cue appears
/// on time and reaction times aren't inflated by polling. Leaving the app
/// mid-test discards the run.
struct ReactionTestView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var run = VigilanceTaskState()
    @State private var now: Millis = AppModel.currentMillis()
    @State private var timer: Task<Void, Never>?
    @State private var saved: VigilanceSession?
    @State private var interrupted = false

    private var cueVisible: Bool { run.phase == .running && run.cueShownAt != nil }

    var body: some View {
        VStack(spacing: Metrics.lg) {
            HStack {
                Button("Close") { close() }
                    .font(.headline)
                    .accessibilityIdentifier("reaction-close")
                Spacer()
                Text(countdown)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, Metrics.sm)
                    .frame(minHeight: Metrics.minimumTouchTarget)
                    .background(Capsule().fill(Palette.cardMuted))
                    .accessibilityLabel("Time remaining \(countdown)")
            }
            area
            summary
        }
        .padding(.horizontal, Metrics.md)
        .padding(.top, Metrics.lg)
        .padding(.bottom, Metrics.xxl)
        .background(Palette.screen.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, run.phase == .running else { return }
            stopClock()
            interrupted = true
            run = VigilanceTaskState()
        }
        .onDisappear { stopClock() }
    }

    private var countdown: String {
        let remaining = run.phase == .running ? max(0, (run.endsAt ?? now) - now) : Vigilance.testDurationMs
        let seconds = Int(ceil(remaining / 1000))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder
    private var area: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous)
        ZStack {
            shape.fill(run.phase == .complete ? Palette.card : (cueVisible ? Palette.primaryButton : Palette.neutralButton))
            shape.strokeBorder(cueVisible ? Palette.primaryButton : Palette.cardBorder, lineWidth: 2)
            switch run.phase {
            case .instructions:
                instructions
            case .running:
                running
            case .complete:
                if let saved { results(saved) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(shape)
        .onTapGesture { tap() }
        .accessibilityElement(children: run.phase == .running ? .ignore : .contain)
        .accessibilityLabel(run.phase == .running ? "Reaction test area" : "")
        .accessibilityValue(run.phase == .running ? (cueVisible ? "TAP!" : "Wait…") : "")
        .accessibilityAddTraits(run.phase == .running ? [.isButton, .allowsDirectInteraction] : [])
        .accessibilityIdentifier("reaction-area")
    }

    private var instructions: some View {
        VStack(spacing: Metrics.sm) {
            Text("Check your reaction speed")
                .font(.title3.bold())
                .foregroundStyle(Palette.textPrimary)
            Text("Wait for the cue, then tap the active area as quickly as you can.")
                .foregroundStyle(Palette.textSecondary)
            if interrupted {
                Text("Test interrupted when the app became inactive. This run was not saved. Start a new test when you can stay in the app for 60 seconds.")
                    .foregroundStyle(Palette.textPrimary)
                    .onAppear {
                        UIAccessibility.post(notification: .announcement, argument: "Test interrupted. This run was not saved.")
                    }
            }
            Button("Start Test") { start() }
                .buttonStyle(.auroraPrimary)
                .frame(maxWidth: 280)
                .accessibilityIdentifier("reaction-start")
        }
        .multilineTextAlignment(.center)
        .padding(Metrics.xl)
    }

    private var running: some View {
        VStack(spacing: Metrics.sm) {
            Text(cueVisible ? "TAP!" : "Wait…")
                .font(.largeTitle.bold())
                .foregroundStyle(cueVisible ? Palette.primaryButtonText : Palette.textPrimary)
            Text(cueVisible ? "Now" : "Hold steady")
                .font(.title2.monospacedDigit())
                .foregroundStyle(cueVisible ? Palette.primaryButtonText : Palette.textSecondary)
            Text(feedbackText)
                .font(.footnote)
                .foregroundStyle(cueVisible ? Palette.primaryButtonText : Palette.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(Metrics.xl)
    }

    private func results(_ session: VigilanceSession) -> some View {
        VStack(spacing: Metrics.sm) {
            Text("Session complete").foregroundStyle(Palette.textSecondary)
            Text("\(session.score)").font(.system(size: 56, weight: .bold).monospacedDigit()).foregroundStyle(Palette.textPrimary)
            Text(session.rating.rawValue).font(.title3.bold()).foregroundStyle(Palette.textPrimary)
            VStack(spacing: 2) {
                Text("Median reaction: \(reaction(session.medianReactionMs))")
                Text("Fastest reaction: \(reaction(session.fastestReactionMs))")
                Text("Lapses: \(session.lapseCount) • False starts: \(session.falseStartCount)")
            }
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
            Text("A quick check of reaction speed, not a medical assessment.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
            HStack(spacing: Metrics.sm) {
                Button("Run Again") { start() }.buttonStyle(.auroraPrimary)
                Button("Done") { close() }.buttonStyle(.auroraSecondary)
            }
            .frame(maxWidth: 360)
        }
        .multilineTextAlignment(.center)
        .padding(Metrics.xl)
    }

    private var summary: some View {
        let counts: (trials: Int, falseStarts: Int, lapses: Int) = {
            if run.phase == .running {
                let lapses = run.trialResults.filter { if case .lapse = $0 { true } else { false } }.count
                return (run.trialResults.count, run.falseStartCount, lapses)
            }
            if let saved { return (saved.trialCount, saved.falseStartCount, saved.lapseCount) }
            return (0, 0, 0)
        }()
        return HStack(spacing: Metrics.sm) {
            stat("Trials", counts.trials)
            stat("False starts", counts.falseStarts)
            stat("Lapses", counts.lapses)
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.bold().monospacedDigit()).foregroundStyle(Palette.textPrimary)
            Text(label).font(.caption).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Metrics.sm)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
        .accessibilityElement(children: .combine)
    }

    private var feedbackText: String {
        switch run.feedback {
        case .falseStart: "Too early. Wait for the cue before tapping."
        case .missed: "Missed cue. A lapse was recorded."
        case .slow: "Slow response. Reactions at \(numberText(Vigilance.lapseMs)) ms or more count as lapses."
        case nil: "Responses under \(numberText(Vigilance.falseStartMs)) ms count as false starts."
        }
    }

    private func reaction(_ ms: Double?) -> String {
        ms.map { "\(jsRoundInt($0)) ms" } ?? "—"
    }

    // MARK: Clock

    private func start() {
        interrupted = false
        saved = nil
        let at = AppModel.currentMillis()
        commit(Vigilance.start(at: at, randomValue: Double.random(in: 0..<1)), at: at)
        scheduleNextEvent()
    }

    private func tap() {
        guard run.phase == .running else { return }
        let at = AppModel.currentMillis()
        let next = Vigilance.tap(run, at: at, randomValue: Double.random(in: 0..<1))
        if next.feedback == .falseStart && next.falseStartCount > run.falseStartCount {
            Haptics.warning()
        } else if next != run {
            Haptics.tap()
        }
        commit(next, at: at)
        scheduleNextEvent()
    }

    private func commit(_ next: VigilanceTaskState, at: Millis) {
        run = next
        now = at
        if next.phase == .complete, saved == nil, let startedAt = next.startedAt {
            let session = Vigilance.buildSession(
                id: RecordID.newVigilanceID(now: at),
                startedAt: startedAt,
                completedAt: at,
                trialResults: next.trialResults,
                falseStartCount: next.falseStartCount
            )
            model.saveReactionTest(session)
            saved = session
            Haptics.success()
        }
    }

    private func scheduleNextEvent() {
        stopClock()
        guard run.phase == .running else { return }
        let current = AppModel.currentMillis()
        var events = [run.endsAt, run.nextCueAt].compactMap { $0 }
        if let cue = run.cueShownAt { events.append(cue + Vigilance.responseWindowMs) }
        if let ends = run.endsAt {
            let remaining = ends - current
            let tick = remaining.truncatingRemainder(dividingBy: 1000)
            events.append(current + (tick == 0 ? 1000 : tick))
        }
        guard let due = events.min() else { return }
        let delay = max(0, due - current)
        timer = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay)))
            guard !Task.isCancelled else { return }
            let fired = AppModel.currentMillis()
            commit(Vigilance.advance(run, at: fired, randomValue: Double.random(in: 0..<1)), at: fired)
            scheduleNextEvent()
        }
    }

    private func stopClock() {
        timer?.cancel()
        timer = nil
    }

    private func close() {
        stopClock()
        if run.phase == .running { run = VigilanceTaskState() }
        dismiss()
    }
}
