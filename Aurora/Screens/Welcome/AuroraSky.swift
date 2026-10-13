import AuroraCore
import SwiftUI

/// Aurora's sky: a time-of-day gradient with soft aurora ribbons that drift
/// while `animating`. Under Reduce Motion, or while the scene isn't active,
/// the ribbons hold still. Decoration only: hidden from VoiceOver and never
/// takes touches.
struct AuroraSky: View {
    let daypart: Welcome.Daypart
    var animating = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            LinearGradient(colors: Sky.stops(daypart), startPoint: .top, endPoint: .bottom)
            if animating && !reduceMotion {
                TimelineView(.animation(minimumInterval: Motion.decorationFrameInterval, paused: scenePhase != .active)) { context in
                    ribbons(phase: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                ribbons(phase: 0)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ribbons(phase: Double) -> some View {
        let colors = Sky.ribbons(daypart)
        let strength = Sky.ribbonStrength(dark: scheme == .dark)
        return Canvas { context, size in
            for (index, color) in colors.enumerated() {
                let depth = Double(index)
                let path = ribbon(
                    in: size,
                    baseline: 0.30 + depth * 0.13,
                    amplitude: 0.07 - depth * 0.012,
                    phase: phase * (0.16 - depth * 0.035) + depth * 1.7
                )
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 28 + depth * 10))
                    layer.fill(path, with: .color(color.opacity(strength - depth * 0.08)))
                }
            }
        }
    }

    /// A band that crests like the wave mark, thicker in the middle.
    private func ribbon(in size: CGSize, baseline: Double, amplitude: Double, phase: Double) -> Path {
        let width = size.width, height = size.height
        let steps = 32
        func y(_ x: Double, offset: Double) -> Double {
            let t = x / max(width, 1)
            return height * (baseline + offset + amplitude * sin(t * .pi * 2.2 + phase) + amplitude * 0.5 * sin(t * .pi * 4.1 - phase * 0.7))
        }
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y(0, offset: 0)))
        for step in 1...steps {
            let x = width * Double(step) / Double(steps)
            path.addLine(to: CGPoint(x: x, y: y(x, offset: 0)))
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let x = width * Double(step) / Double(steps)
            let thickness = 0.05 + 0.07 * sin(x / max(width, 1) * .pi)
            path.addLine(to: CGPoint(x: x, y: y(x, offset: thickness)))
        }
        path.closeSubpath()
        return path
    }
}

extension View {
    /// Liquid Glass on iOS 26 and later; the regular system material with a
    /// card border before that.
    @ViewBuilder func auroraGlass(cornerRadius: CGFloat = Metrics.heroRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Palette.cardBorder.opacity(0.6)))
        }
    }
}

extension Welcome.Daypart {
    static func current(clock: LocalClock, now: Millis) -> Welcome.Daypart {
        Welcome.Daypart(hour: clock.hour(now))
    }
}
