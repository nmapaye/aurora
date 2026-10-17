import AuroraCore
import GameController
import SwiftUI

/// The 30-second Reaction Test, always presented full screen.
///
/// While it runs the whole screen is the tap surface except Close: a UIKit
/// view stamps each touch at touch-down, and a display link stamps each cue
/// when its frame is shown (`ReactionRun`). Leaving the app mid-test
/// discards the run.
///
/// Close mid-test asks "End test?" in a system alert. The clock pauses while
/// it is open (the time left is kept); Keep going withdraws a cue that was on
/// screen, unscored, and starts a new 1–4 s wait. End discards the run.
struct ReactionTestView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var run = ReactionRun()
    @State private var saved: VigilanceSession?
    @State private var interrupted = false
    @State private var confirmingEnd = false

    private var running: Bool { run.state.phase == .running }

    var body: some View {
        ZStack {
            if running {
                ReactionRunningScreen(run: run) { askToEnd() }
            } else {
                card
            }
        }
        .background(Palette.screen.ignoresSafeArea())
        .alert("End test?", isPresented: $confirmingEnd) {
            Button("End", role: .destructive) { end() }
                .accessibilityIdentifier("reaction-end-confirm")
            Button("Keep going", role: .cancel) { run.resume() }
                .accessibilityIdentifier("reaction-keep-going")
        } message: {
            Text("This run won’t be saved.")
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, running else { return }
            confirmingEnd = false
            run.discard()
            interrupted = true
        }
        .onAppear { run.onComplete = { state, at in save(state, completedAt: at) } }
        .onDisappear { run.stop() }
    }

    // MARK: Instructions and results

    private var card: some View {
        VStack(spacing: Metrics.lg) {
            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .font(.headline)
                    .frame(minHeight: Metrics.minimumTouchTarget)
                    .accessibilityIdentifier("reaction-close")
                Spacer()
            }
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous).fill(Palette.card)
                RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous).strokeBorder(Palette.cardBorder, lineWidth: 1)
                // Centred when it fits; scrolls at the largest text sizes.
                ViewThatFits(in: .vertical) {
                    cardContent
                    ScrollView { cardContent }
                }
            }
        }
        .padding(.horizontal, Metrics.md)
        .padding(.top, Metrics.sm)
        .padding(.bottom, Metrics.md)
        .frame(maxWidth: Metrics.contentMaxWidth)
    }

    private var cardContent: some View {
        Group {
            if run.state.phase == .complete {
                if let saved { ReactionResults(session: saved, again: start, done: { dismiss() }) } else { notSaved }
            } else {
                instructions
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Metrics.xl)
    }

    private var instructions: some View {
        VStack(spacing: Metrics.sm) {
            Text("Check your reaction speed")
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Wait for the cue, then tap anywhere on the screen as quickly as you can. It takes 30 seconds.")
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Only with a keyboard connected (read when the screen is drawn).
            if GCKeyboard.coalesced != nil {
                Text("With a keyboard, press Space or Return.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if interrupted {
                Text("Test interrupted when the app became inactive. This run was not saved. Start a new test when you can stay in the app for 30 seconds.")
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
    }

    private var notSaved: some View {
        VStack(spacing: Metrics.md) {
            Text("No timed reactions were recorded, so this run wasn’t saved.")
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            Button("Run Again") { start() }.buttonStyle(.auroraPrimary)
        }
    }

    // MARK: Run

    private func start() {
        interrupted = false
        saved = nil
        run.start()
    }

    private func askToEnd() {
        guard running else { dismiss(); return }
        run.pause()
        confirmingEnd = true
    }

    private func end() {
        run.discard()
        dismiss()
    }

    private func save(_ final: VigilanceTaskState, completedAt: Millis) {
        guard saved == nil, let startedAt = final.startedAt else { return }
        let session = Vigilance.buildSession(
            id: RecordID.newVigilanceID(now: completedAt),
            startedAt: startedAt,
            completedAt: completedAt,
            trials: final.trials,
            falseStarts: final.falseStarts,
            deviceModel: ReactionRun.deviceModel,
            input: run.input
        )
        let hasTimedResponse = Vigilance.hasTimedResponse(final)
        model.saveReactionTest(session, hasTimedResponse: hasTimedResponse)
        if hasTimedResponse, model.mutationFailure == nil {
            saved = session
            Haptics.success()
        }
    }
}

/// The running test: the cue colour fills the screen, every touch outside
/// Close lands on the touch surface, and the text above it ignores touches.
private struct ReactionRunningScreen: View {
    let run: ReactionRun
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cue: Bool { run.cueVisible }

    var body: some View {
        ZStack {
            (cue ? Palette.primaryButton : Palette.neutralButton).ignoresSafeArea()
            if !reduceMotion {
                Palette.statusWarningBackground
                    .ignoresSafeArea()
                    .keyframeAnimator(initialValue: 0.0, trigger: run.falseStartFlash) { content, value in
                        content.opacity(value)
                    } keyframes: { _ in
                        LinearKeyframe(1.0, duration: 0.01)
                        LinearKeyframe(0.0, duration: 0.35)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            ReactionTouchSurface(accessibilityValue: cue ? "Tap now" : "Wait for the cue") { uptime, input in
                run.touchDown(uptime: uptime, input: input)
            } onEscape: { close() }
            .ignoresSafeArea()
            prompt
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            chrome
        }
    }

    private var prompt: some View {
        VStack(spacing: Metrics.sm) {
            Text(cue ? "Tap now" : "Wait for the cue")
                .font(.largeTitle.bold())
                .foregroundStyle(cue ? Palette.primaryButtonText : Palette.textPrimary)
            Text(feedback ?? " ")
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(feedbackColor)
        }
        .multilineTextAlignment(.center)
        .padding(Metrics.xl)
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
                    .font(.headline)
                    .foregroundStyle(cue ? Palette.primaryButtonText : Palette.tint)
                    .frame(minWidth: Metrics.minimumTouchTarget, minHeight: Metrics.minimumTouchTarget)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("reaction-close")
                Spacer()
                Text(countdown)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(cue ? Palette.primaryButtonText : Palette.textPrimary)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Time remaining \(countdown)")
            }
            Spacer()
            if ReactionRun.holdsCue {
                Text("touches \(run.touchCount) early \(run.state.falseStartCount) ignored \(run.state.ignoredTapCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("reaction-diagnostics")
            }
        }
        .padding(.horizontal, Metrics.md)
        .padding(.top, Metrics.xs)
    }

    private var countdown: String {
        String(format: "%d:%02d", run.secondsLeft / 60, run.secondsLeft % 60)
    }

    private var feedback: String? {
        switch run.state.feedback {
        case .tooEarly(let count): "Too early (\(count))"
        case .reaction(let ms): "\(jsRoundInt(ms)) ms"
        case .tooLate: "Too late"
        case .missed: "Missed"
        case nil: nil
        }
    }

    private var feedbackColor: Color {
        if cue { return Palette.primaryButtonText }
        switch run.state.feedback {
        case .tooEarly, .tooLate, .missed: return Palette.statusWarningText
        default: return Palette.textSecondary
        }
    }
}

/// The saved session's score and counts.
private struct ReactionResults: View {
    let session: VigilanceSession
    let again: () -> Void
    let done: () -> Void
    /// The score scales with Dynamic Type from 56 pt at the default size.
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 56

    var body: some View {
        VStack(spacing: Metrics.sm) {
            Text("Session complete").foregroundStyle(Palette.textSecondary)
            Text("\(session.score)")
                .font(.system(size: scoreSize, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
            Text(session.rating.rawValue).font(.title3.bold()).foregroundStyle(Palette.textPrimary)
            VStack(spacing: 2) {
                Text("Median reaction: \(reaction(session.medianReactionMs))")
                Text("Fastest reaction: \(reaction(session.fastestReactionMs))")
                Text("Cues: \(session.trialCount) • Lapses: \(session.lapseCount) • False starts: \(session.falseStartCount)")
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(Palette.textSecondary)
            Text("A quick check of reaction speed, not a medical assessment.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Metrics.sm) { buttons }
                VStack(spacing: Metrics.sm) { buttons }
            }
            .frame(maxWidth: 360)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder private var buttons: some View {
        Button("Run Again", action: again).buttonStyle(.auroraPrimary)
        Button("Done", action: done).buttonStyle(.auroraSecondary)
    }

    private func reaction(_ ms: Double?) -> String {
        ms.map { "\(jsRoundInt($0)) ms" } ?? "—"
    }
}
