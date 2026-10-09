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
