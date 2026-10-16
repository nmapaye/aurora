import SwiftUI

/// Clearing the conversation, on screen: the screen's own colour rises from
/// the bottom under a soft edge, wiping the messages away newest first,
/// with a faint aurora band riding the edge. Running it back brings the
/// welcome in from the top. Under Reduce Motion it is a plain fade.
///
/// Drawn over the conversation rather than applied to it: a mask or blur
/// on the scroll view, even at rest, moved where scrolled cards landed
/// under the navigation bar on iOS 26 (CI). At 0 it draws nothing.
struct ConversationErase: View, Animatable {
    /// 0 shows everything; 1 has wiped everything.
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

    var body: some View {
        GeometryReader { geometry in
            if progress > 0 {
                if reduceMotion {
                    Palette.screen.opacity(progress)
                } else {
                    wash(geometry.size.height)
                    band(geometry.size.height)
                }
            }
        }
        // The wash runs past the bottom mid-sweep; keep it off the composer.
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the middle of the soft edge is: a feather below the bottom at
    /// 0, a feather above the top at 1.
    private func edge(_ height: CGFloat) -> CGFloat {
        (height + Self.feather) * (1 - progress) - Self.feather / 2
    }

    /// Clear above the edge, the screen colour below it.
    private func wash(_ height: CGFloat) -> some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Palette.screen.opacity(0), Palette.screen], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.feather)
            Palette.screen
        }
        .frame(height: height + Self.feather)
        .offset(y: edge(height) - Self.feather / 2)
    }

    /// Strongest mid-sweep, gone at either end.
    private func band(_ height: CGFloat) -> some View {
        LinearGradient(colors: [.clear, Palette.auroraMint.opacity(0.35), Palette.auroraIndigo.opacity(0.18), .clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: Self.feather)
            .blur(radius: 18)
            .offset(y: edge(height) - Self.feather / 2)
            .opacity(sin(.pi * progress))
    }
}
