import AuroraCore
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
///
/// Without touch: Space or Return on a hardware keyboard responds, stamped
/// with the key's `UIPress.timestamp`, and activating the area (Full
/// Keyboard Access, Switch Control, VoiceOver) responds at activation time.
/// Both report `.keyboard`, so those sessions only compare with each other.
struct ReactionTouchSurface: UIViewRepresentable {
    /// Read by VoiceOver: "Wait for the cue" or "Tap now".
    var accessibilityValue: String
    var onResponse: (TimeInterval, VigilanceInput) -> Void
    /// Escape, and the accessibility escape (VoiceOver's scrub, Full
    /// Keyboard Access): the same as Close.
    var onEscape: () -> Void

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.onResponse = onResponse
        view.onEscape = onEscape
        return view
    }

    func updateUIView(_ view: SurfaceView, context: Context) {
        view.onResponse = onResponse
        view.onEscape = onEscape
        view.accessibilityValue = accessibilityValue
    }

    final class SurfaceView: UIView {
        var onResponse: ((TimeInterval, VigilanceInput) -> Void)?
        var onEscape: (() -> Void)?
        /// The keys that answer a cue.
        private static let responseKeys: Set<UIKeyboardHIDUsage> = [.keyboardSpacebar, .keyboardReturnOrEnter, .keypadEnter]

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
            if let earliest = touches.map(\.timestamp).min() { onResponse?(earliest, .touch) }
            // Not forwarded: nothing behind the surface should react.
        }

        // MARK: Keyboard and assistive input

        override var canBecomeFirstResponder: Bool { true }

        /// First responder as soon as it's on screen, so a key press reaches
        /// it without a tap first.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { DispatchQueue.main.async { [weak self] in self?.becomeFirstResponder() } }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            // This view is first responder, so Escape arrives here; a
            // SwiftUI shortcut on Close didn't fire while it held focus.
            if presses.contains(where: { $0.key?.keyCode == .keyboardEscape }) { onEscape?(); return }
            let responses = presses.filter { $0.key.map { Self.responseKeys.contains($0.keyCode) } == true }
            guard let earliest = responses.map(\.timestamp).min() else { return super.pressesBegan(presses, with: event) }
            onResponse?(earliest, .keyboard)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if !presses.contains(where: { $0.key.map { Self.responseKeys.contains($0.keyCode) } == true }) { super.pressesEnded(presses, with: event) }
        }

        /// Full Keyboard Access's Space, Switch Control and VoiceOver's
        /// double tap. The second of a key press and its activation arrives
        /// within the double-tap window and is ignored.
        override func accessibilityPerformEscape() -> Bool {
            onEscape?()
            return true
        }

        override func accessibilityActivate() -> Bool {
            onResponse?(ProcessInfo.processInfo.systemUptime, .keyboard)
            return true
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}
    }
}
