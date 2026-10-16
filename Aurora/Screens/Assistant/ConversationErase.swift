import SwiftUI

/// Clearing the conversation, on screen: a soft edge lifts from the bottom
/// and the messages blur away beneath it, newest first, with a faint
/// aurora band riding the edge. Running it back brings the welcome in
/// from the top. Under Reduce Motion it is a plain fade.
struct ConversationErase: ViewModifier, Animatable {
    /// 0 shows everything; 1 has erased everything.
    var progress: Double
    let reduceMotion: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// The soft part of the edge, in points.
    private static let feather: CGFloat = 140

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .timingCurve(0.45, 0, 0.2, 1, duration: 0.7)
    }

    static func returning(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0)
    }

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(1 - progress)
        } else {
            content
                .blur(radius: 8 * progress)
                .scaleEffect(1 - 0.015 * progress, anchor: .top)
                .mask(alignment: .top) { GeometryReader { mask($0.size.height) } }
                .overlay(alignment: .top) { GeometryReader { band($0.size) } }
        }
    }

    /// Opaque above the edge, fading out over the feather below it. At 0 the
    /// edge sits a feather below the bottom; at 1 a feather above the top.
    private func mask(_ height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.feather)
        }
        .frame(height: height + Self.feather)
        .offset(y: -(height + Self.feather) * progress)
    }

    /// Strongest mid-sweep, gone at either end.
    private func band(_ size: CGSize) -> some View {
        let edge = (size.height + Self.feather) * (1 - progress) - Self.feather / 2
        return LinearGradient(colors: [.clear, Palette.auroraMint.opacity(0.35), Palette.auroraIndigo.opacity(0.18), .clear],
                              startPoint: .top, endPoint: .bottom)
            .frame(height: Self.feather)
            .blur(radius: 18)
            .offset(y: edge - Self.feather / 2)
            .opacity(sin(.pi * progress))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
