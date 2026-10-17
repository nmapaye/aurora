import SwiftUI
import UIKit

/// The Reaction Test's tap surface: a plain UIKit view that reports every
/// touch-down from `touchesBegan`, with the touch's hardware timestamp
/// (`UITouch.timestamp`, seconds of system uptime).
///
/// SwiftUI's tap gesture fires on touch-up and fails for long presses, and a
/// sheet's dismiss pan takes short slides; a two-finger touch reached no
/// SwiftUI gesture at all. `touchesBegan` sees all of them at touch-down.
/// Touches that begin together (two fingers) arrive as one call and report
/// their earliest timestamp; a finger that lands later reports on its own,
/// and the state machine ignores it as the rest of a double tap.
struct ReactionTouchSurface: UIViewRepresentable {
    /// Read by VoiceOver: "Wait for the cue" or "Tap now".
    var accessibilityValue: String
    var onTouchDown: (TimeInterval) -> Void

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.onTouchDown = onTouchDown
        return view
    }

    func updateUIView(_ view: SurfaceView, context: Context) {
        view.onTouchDown = onTouchDown
        view.accessibilityValue = accessibilityValue
    }

    final class SurfaceView: UIView {
        var onTouchDown: ((TimeInterval) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            isExclusiveTouch = false
            backgroundColor = .clear
            isAccessibilityElement = true
            accessibilityIdentifier = "reaction-area"
            accessibilityLabel = "Reaction test area"
            // VoiceOver passes touches straight through, so a cue can be
            // answered without double-tapping.
            accessibilityTraits = [.allowsDirectInteraction]
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let earliest = touches.map(\.timestamp).min() { onTouchDown?(earliest) }
            // Not forwarded: nothing behind the surface should react.
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}
    }
}
