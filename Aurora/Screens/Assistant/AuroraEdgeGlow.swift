import SwiftUI
import UIKit

/// Real work lights the perimeter; its frozen final frame fades away afterward.
/// No motion timer runs at rest, in the background, or with Reduce Motion enabled.
struct AuroraEdgeGlow: View {
    let active: Bool
    /// False draws the Reduce Motion treatment (Design Gallery review).
    var allowsMotion = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var still: Bool { reduceMotion || !allowsMotion }

    var body: some View {
        ZStack {
            if active && !still && scenePhase == .active {
                TimelineView(.animation(minimumInterval: Motion.decorationFrameInterval)) { context in
                    edge(phase: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                // Rendered when work ends, is stopped or fails, or the scene
                // leaves active: the bands hold where the timeline left them,
                // so the fade starts from the last frame instead of jumping
                // to a stale one. Reduce Motion always draws the same frame.
                edge(phase: still ? 0 : Date.now.timeIntervalSinceReferenceDate)
            }
        }
        .opacity(active ? 1 : 0)
        .animation(still || scenePhase != .active ? nil : .easeInOut(duration: active ? Motion.processingFadeIn : Motion.processingFadeOut), value: active)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The window's own corners on iOS 26, so the light follows an iPhone's
    /// display, an iPad's smaller corners and a Stage Manager window alike.
    /// Earlier, and wherever no container shape resolves, a radius for the
    /// idiom: a fixed 42 pt was far too round on iPad.
    @ViewBuilder private func edge(phase: Double) -> some View {
        let fallback: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 18 : 42
        if #available(iOS 26, *) {
            EdgeBands(shape: ConcentricRectangle(corners: .concentric(minimum: .fixed(fallback)), isUniform: true), phase: phase)
        } else {
            EdgeBands(shape: RoundedRectangle(cornerRadius: fallback, style: .continuous), phase: phase)
        }
    }
}

/// Three bands travelling around the perimeter. The halos of all three
/// share one blurred layer and the cores draw crisp: six full-window blurs
/// per frame, at 30 fps, were the glow's whole cost.
private struct EdgeBands<Perimeter: Shape>: View {
    let shape: Perimeter
    let phase: Double

    private struct Band: Identifiable {
        let id: Int
        let start: Double
        let length: Double
        let width: Double
        let color: Color
    }

    private var bands: [Band] {
        (0..<3).map { band in
            let offset = Double(band)
            let brightness = 0.55 + 0.16 * sin(phase * 0.7 + offset)
            return Band(
                id: band,
                start: (phase / 10 + offset / 3).truncatingRemainder(dividingBy: 1),
                length: 0.19 + 0.045 * sin(phase * 0.65 + offset * 2),
                width: 3.5 + 1.2 * sin(phase * 0.8 + offset * 2),
                color: Palette.auroraColors[band].opacity(brightness)
            )
        }
    }

    var body: some View {
        let bands = bands
        ZStack {
            shape.stroke(Palette.auroraTeal.opacity(0.14), lineWidth: 2)
            ZStack {
                ForEach(bands) { band in segments(band, width: band.width + 10, opacity: 0.55) }
            }
            .compositingGroup()
            .blur(radius: 10)
            ForEach(bands) { band in segments(band, width: band.width, opacity: 1) }
        }
        .padding(5)
    }

    /// Split at the perimeter seam so each traveling band wraps continuously.
    @ViewBuilder private func segments(_ band: Band, width: Double, opacity: Double) -> some View {
        let style = StrokeStyle(lineWidth: width, lineCap: .round)
        shape.trim(from: band.start, to: min(band.start + band.length, 1))
            .stroke(band.color.opacity(opacity), style: style)
        if band.start + band.length > 1 {
            shape.trim(from: 0, to: band.start + band.length - 1)
                .stroke(band.color.opacity(opacity), style: style)
        }
    }
}
