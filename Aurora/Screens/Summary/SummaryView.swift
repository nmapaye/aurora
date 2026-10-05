import AuroraCore
import SwiftUI

/// Summary: Estimated Alertness and today's caffeine curve, then three pinned
/// signals, each with its date and source.
struct SummaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let state = model.state
        let now = model.now
        let inputs = EstimateInputs(prefs: state.prefs, clock: model.clock)
        let estimate = Summary.estimateAlertness(at: now, doses: state.doses, sleeps: state.sleeps, inputs: inputs)

        AppScreen(title: "Summary") {
            sampleStatus(state)
            WideColumns {
                todayPanel(estimate: estimate)
            } trailing: {
                pinned(state, now: now)
            }
        }
    }

    @ViewBuilder
    private func sampleStatus(_ state: AppState) -> some View {
        if state.demoMode {
            HStack(spacing: Metrics.xs) {
                Image(systemName: "sparkles").foregroundStyle(Palette.textSecondary).accessibilityHidden(true)
                Text("Showing sample data: example records, not yours.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
                Button("Clear Samples") { model.clearSampleData() }
                    .font(.footnote.weight(.semibold))
                    .accessibilityLabel("Clear Sample Data")
            }
            .accessibilityIdentifier("summary-sample-status")
        } else if state.doses.isEmpty && state.sleeps.isEmpty && state.vigilanceSessions.isEmpty {
            HStack(spacing: Metrics.xs) {
                Text("Nothing recorded yet. You can explore with a labeled sample week.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
                Button("Load Sample Data") { model.loadSampleData() }
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private func todayPanel(estimate: AlertnessEstimate) -> some View {
        VStack(alignment: .leading, spacing: Metrics.md) {
            HStack {
                SectionLabel(text: "Today")
                Spacer()
                Button("Details") { router.tab = .insights }
                    .font(.subheadline.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: Metrics.md) {
                let stacked = typeSize.isAccessibilitySize
                let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.md)) : AnyLayout(HStackLayout(spacing: Metrics.md))
                layout {
                    AlertnessRing(estimate: estimate)
                        .frame(width: 104, height: 104)
                    alertnessCopy(estimate)
                }
                Divider().overlay(Palette.separator)
                SectionLabel(text: "Caffeine Today")
                CaffeineTodayChart()
            }
            .padding(Metrics.md)
            .background(RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous).strokeBorder(Palette.cardBorder))
        }
    }

    private func alertnessCopy(_ estimate: AlertnessEstimate) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xxs) {
            SectionLabel(text: "Estimated Alertness")
            switch estimate {
            case .estimated(_, let hours, let sample):
                Text("From \(formatSleepHours(hours)) of sleep")
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Text(sample
                     ? "Includes Sample Data. Plus active caffeine and time of day. Not a measurement."
                     : "Plus active caffeine and time of day. Not a measurement.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .needsSleep:
                Text("No recent sleep")
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Text("Add sleep from the last 24 hours to see an estimate.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Sleep") { router.tab = .sleep }
                    .buttonStyle(.bordered)
                    .padding(.top, Metrics.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pinned(_ state: AppState, now: Millis) -> some View {
        VStack(alignment: .leading, spacing: Metrics.md) {
            SectionLabel(text: "Pinned")
            SignalCard(
                model: SummarySignals.caffeineLogged(doses: state.doses, now: now, clock: model.clock, formatTime: model.text.clockTime),
                symbol: "cup.and.saucer.fill",
                accent: Palette.caffeineAccent
            ) { router.tab = .log }
            SignalCard(
                model: SummarySignals.sleep(sleeps: state.sleeps, targetSleepHours: state.prefs.targetSleep, now: now, clock: model.clock, text: model.text),
                symbol: "bed.double.fill",
                accent: Palette.sleepAccent
            ) { router.tab = .sleep }
            SignalCard(
                model: SummarySignals.reactionTest(sessions: state.vigilanceSessions, now: now, clock: model.clock, text: model.text),
                symbol: "speedometer",
                accent: Palette.vigilanceAccent
            ) { router.showReactionTest = true }
        }
    }
}

/// Side by side on a wide iPad window, stacked everywhere else.
struct WideColumns<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.isWideLayout) private var wide

    var body: some View {
        if wide {
            HStack(alignment: .top, spacing: Metrics.xl) {
                VStack(alignment: .leading, spacing: Metrics.xl, content: leading)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: Metrics.xl, content: trailing)
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.xl) {
                leading()
                trailing()
            }
        }
    }
}

/// The alertness ring. Without recent sleep it shows no score at all.
struct AlertnessRing: View {
    let estimate: AlertnessEstimate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let score = estimate.score
        ZStack {
            Circle().stroke(Palette.cardMuted, lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(score ?? 0) / 100)
                .stroke(Palette.tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.36), value: score)
            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "–")
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(score == nil ? Palette.textTertiary : Palette.textPrimary)
                Text("Estimate")
                    .font(.caption2)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Summary.describe(estimate))
        .accessibilityIdentifier("alertness-ring")
    }
}
