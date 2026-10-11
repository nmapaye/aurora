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
    @State private var wave: CGFloat = 0
    @State private var dot = false
    @State private var cardIn = false

    var body: some View {
        let leaving = !showing && !reduceMotion
        ZStack {
            AuroraSky(daypart: content.daypart, animating: showing)
                .scaleEffect(leaving ? 1.06 : 1)
            VStack(spacing: Metrics.xl) {
                Spacer()
                DrawnAuroraMark(wave: reduceMotion ? 1 : wave, dot: reduceMotion || dot)
                    .frame(width: 72, height: 72)
                    .scaleEffect(leaving ? 1.25 : 1)
                    .shadow(color: Palette.auroraTeal.opacity(leaving ? 0.6 : 0.25), radius: leaving ? 24 : 10)
                card
                    .opacity(cardIn ? 1 : 0)
                    .offset(y: leaving ? -36 : (cardIn || reduceMotion ? 0 : 14))
                    .blur(radius: leaving ? 8 : 0)
                Spacer()
                Spacer()
            }
            .padding(.horizontal, Metrics.xl)
            .frame(maxWidth: Metrics.contentMaxWidth)
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: dot) { _, shown in shown }
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

    /// The mark draws itself in, its dot pops, then the greeting rises.
    private func play() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: Motion.controlDuration)) { cardIn = true }
        } else {
            withAnimation(.easeInOut(duration: 0.9)) { wave = 1 }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55).delay(0.75)) { dot = true }
            withAnimation(.spring(duration: 0.55, bounce: 0.15).delay(0.55)) { cardIn = true }
        }
        #if DEBUG
        // UI tests and design review: stay until tapped.
        if ProcessInfo.processInfo.arguments.contains("-AuroraWelcomeHold") { return }
        #endif
        try? await Task.sleep(for: .seconds(Welcome.Presentation.holdSeconds))
        guard !Task.isCancelled else { return }
        onSkip()
    }
}

/// The wave mark drawn as a path, so the welcome can draw it in: the ribbon
/// traces from left to right, then the dot appears. Same geometry as
/// `AuroraMark`.
struct DrawnAuroraMark: View {
    var wave: CGFloat
    var dot: Bool

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / 128
            ZStack(alignment: .topLeading) {
                WavePath()
                    .trim(from: 0, to: wave)
                    .stroke(Palette.tint, style: StrokeStyle(lineWidth: 13 * scale, lineCap: .round, lineJoin: .round))
                Circle()
                    .fill(Palette.tint)
                    .frame(width: 18 * scale, height: 18 * scale)
                    .offset(x: 27 * scale, y: 29 * scale)
                    .scaleEffect(dot ? 1 : 0.01, anchor: .center)
                    .opacity(dot ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }

    private struct WavePath: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = min(rect.width, rect.height) / 128
            var wave = Path()
            wave.move(to: CGPoint(x: 30, y: 84))
            wave.addCurve(to: CGPoint(x: 74, y: 82), control1: CGPoint(x: 46, y: 48), control2: CGPoint(x: 60, y: 48))
            wave.addCurve(to: CGPoint(x: 102, y: 56), control1: CGPoint(x: 82, y: 62), control2: CGPoint(x: 92, y: 54))
            return wave.applying(CGAffineTransform(scaleX: scale, y: scale))
        }
    }
}
