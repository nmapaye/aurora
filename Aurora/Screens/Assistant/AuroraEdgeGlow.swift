import SwiftUI

/// Real work lights the perimeter; its frozen final frame fades away afterward.
/// No motion timer runs at rest, in the background, or with Reduce Motion enabled.
struct AuroraEdgeGlow: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var frozenPhase = Date().timeIntervalSinceReferenceDate

    var body: some View {
        ZStack {
            if active && !reduceMotion && scenePhase == .active {
                TimelineView(.animation(minimumInterval: Motion.decorationFrameInterval)) { context in
                    edge(phase: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                edge(phase: reduceMotion ? 0 : frozenPhase)
            }
        }
        .opacity(active ? 1 : 0)
        .animation(reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: active ? Motion.processingFadeIn : Motion.processingFadeOut), value: active)
        .onChange(of: active) { _, isActive in
            if !isActive { frozenPhase = Date().timeIntervalSinceReferenceDate }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { frozenPhase = Date().timeIntervalSinceReferenceDate }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func edge(phase: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42)
                .stroke(Palette.auroraTeal.opacity(0.14), lineWidth: 2)
            ForEach(0..<3) { band in
                let offset = Double(band)
                let start = (phase / 10 + offset / 3).truncatingRemainder(dividingBy: 1)
                let length = 0.19 + 0.045 * sin(phase * 0.65 + offset * 2)
                let width = 3.5 + 1.2 * sin(phase * 0.8 + offset * 2)
                let brightness = 0.55 + 0.16 * sin(phase * 0.7 + offset)
                let color = Palette.auroraColors[band]
                bandShape(start: start, length: length, width: width + 10, color: color.opacity(brightness * 0.55))
                    .blur(radius: 10)
                bandShape(start: start, length: length, width: width, color: color.opacity(brightness))
                    .blur(radius: 1.5)
            }
        }
        .padding(5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Split at the perimeter seam so each traveling band wraps continuously.
    private func bandShape(start: Double, length: Double, width: Double, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42)
                .trim(from: start, to: min(start + length, 1))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            if start + length > 1 {
                RoundedRectangle(cornerRadius: 42)
                    .trim(from: 0, to: start + length - 1)
                    .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }
}
