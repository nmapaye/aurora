import AuroraCore
import SwiftUI

/// What the welcome says, chosen once per cold launch.
struct WelcomeContent: Equatable {
    let daypart: Welcome.Daypart
    let greeting: String
    let evidence: Welcome.Evidence?
}

/// Shown once per cold launch over the already-loaded conversation: the sky,
/// the wave mark, a greeting and at most one recorded fact with its source
/// and time. It ends by itself after `Welcome.Presentation.holdSeconds`, and
/// any tap ends it at once. The parent owns hit-testing, so a skip makes the
/// conversation usable in the same update; any fade is decoration only.
struct WelcomeOverlay: View {
    let content: WelcomeContent
    /// Drift the sky only while the welcome is actually up.
    let showing: Bool
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            AuroraSky(daypart: content.daypart, animating: showing)
            VStack(spacing: Metrics.xl) {
                Spacer()
                AuroraMark()
                    .frame(width: 64, height: 64)
                    .scaleEffect(revealed || reduceMotion ? 1 : 0.94)
                card
                    .offset(y: revealed || reduceMotion ? 0 : 8)
                Spacer()
                Spacer()
            }
            .opacity(revealed ? 1 : 0)
            .padding(.horizontal, Metrics.xl)
            .frame(maxWidth: Metrics.contentMaxWidth)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSkip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens your conversation.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSkip() }
        .accessibilityIdentifier("welcome")
        .task { await play() }
    }

    private var spoken: String {
        [content.greeting, content.evidence?.spoken ?? Welcome.neutralLine].joined(separator: ". ")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(content.greeting)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let evidence = content.evidence {
                Label {
                    Text(evidence.text)
                        .font(Typography.evidence.monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: evidence.symbol).foregroundStyle(Palette.tint)
                }
                Text("\(evidence.date) · \(evidence.source)")
                    .font(Typography.source.monospacedDigit())
                    .foregroundStyle(evidence.sample ? Palette.caffeineAccent : Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Welcome.neutralLine)
                    .font(Typography.explanation)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.lg)
        .auroraGlass()
    }

    private func play() async {
        withAnimation(reduceMotion ? .easeOut(duration: Motion.controlDuration) : .spring(duration: Motion.contentDuration, bounce: 0)) { revealed = true }
        #if DEBUG
        // UI tests and design review: stay until tapped.
        if ProcessInfo.processInfo.arguments.contains("-AuroraWelcomeHold") { return }
        #endif
        try? await Task.sleep(for: .seconds(Welcome.Presentation.holdSeconds))
        guard !Task.isCancelled else { return }
        onSkip()
    }
}
