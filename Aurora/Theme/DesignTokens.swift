import SwiftUI

enum Typography {
    static let cardTitle: Font = .headline
    static let evidence: Font = .body
    static let explanation: Font = .subheadline
    static let source: Font = .caption
    /// Field and metric labels beside or above a value.
    static let label: Font = .subheadline
    /// A recorded quantity inside a card; pair with `.monospacedDigit()`.
    static let value: Font = .title3.weight(.semibold)
    /// The lead quantity of an evidence card; pair with `.monospacedDigit()`.
    static let heroValue: Font = .title2.weight(.semibold)
}

enum Motion {
    static let controlDuration = 0.18
    static let contentDuration = 0.25
    static let processingFadeIn = 0.45
    static let processingFadeOut = 0.70
    static let decorationFrameInterval = 1.0 / 30.0

    static func content(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: contentDuration)
    }

    /// Pressed feedback on custom button styles. Kept under Reduce Motion
    /// because it is an opacity change, not movement.
    static let press: Animation = .easeOut(duration: controlDuration)
    /// Press-down and release: quick to compress, a little spring on the way
    /// back so the control feels physical. Reduce Motion uses `press`.
    static let pressSpring: Animation = .spring(response: 0.22, dampingFraction: 0.62)
    static let pressedScale: CGFloat = 0.96

    /// A card changing state in place: draft to saved, saved to removed,
    /// a disclosure opening. Spring with no bounce so it can be interrupted
    /// mid-flight by the next change without overshooting.
    static func stateChange(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(duration: contentDuration, bounce: 0)
    }

    /// Content swapped by a state change. Crossfade only under Reduce Motion.
    static func stateTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }
}

/// Every custom control's touch response: it compresses under the finger
/// with a light tap, then springs back. Under Reduce Motion it dims instead
/// of scaling. Haptics follow the system setting.
struct PressFeedback: ViewModifier {
    let isPressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? Motion.pressedScale : 1)
            .opacity(isPressed ? (reduceMotion ? 0.7 : 0.88) : 1)
            .animation(reduceMotion ? Motion.press : Motion.pressSpring, value: isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: isPressed) { _, pressed in pressed && isEnabled }
    }
}

extension View {
    func pressFeedback(_ isPressed: Bool) -> some View { modifier(PressFeedback(isPressed: isPressed)) }
}

/// For tappable rows, chips and cards that draw their own surface.
struct AuroraPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .pressFeedback(configuration.isPressed)
    }
}

extension ButtonStyle where Self == AuroraPressStyle {
    static var auroraPress: AuroraPressStyle { AuroraPressStyle() }
}
