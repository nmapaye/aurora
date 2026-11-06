import SwiftUI
import UIKit

/// A primary button whose tap is read by UIKit's own touch handling, not by
/// SwiftUI's button gesture. Used for a draft card's Save.
///
/// #71 on iPad: with a card field focused and a hardware keyboard attached,
/// the Save tap itself made UIKit minimize the software keyboard
/// (`-[UIKeyboard setMinimized:]`, visual mode 1 -> 2, about 30 ms after the
/// touch lifted). The touch reached Aurora and Save didn't move, yet the
/// SwiftUI Button's action never ran. A UIKit text field tapped the same way
/// still took focus, so UIKit's touch delivery survives the minimize and the
/// SwiftUI press is what gets lost. Here the action runs from `touchesEnded`,
/// inside UIKit's delivery of the lift, before the keyboard change is handled.
///
/// The tap is still deliberate: it commits on lift, only within the button
/// and a finger's slack, and never when the conversation scrolls (a scroll
/// view cancels a plain view's touches when it starts dragging, which it
/// doesn't do for a UIControl). VoiceOver, Switch Control, Voice Control and
/// Full Keyboard Access activate it through `accessibilityActivate`.
struct PrimaryTouchButton: View {
    let title: String
    let identifier: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var pressed = false

    var body: some View {
        PrimaryButtonSurface(label: Text(title), isPressed: pressed)
            // The touch view over it is the button to accessibility and UI tests.
            .accessibilityHidden(true)
            .overlay { Touches(title: title, identifier: identifier, enabled: isEnabled, pressed: $pressed, action: action) }
    }

    private struct Touches: UIViewRepresentable {
        let title: String
        let identifier: String
        let enabled: Bool
        @Binding var pressed: Bool
        let action: () -> Void

        func makeUIView(context: Context) -> TouchView { TouchView() }

        func updateUIView(_ view: TouchView, context: Context) {
            let pressed = $pressed
            view.onPress = { if pressed.wrappedValue != $0 { pressed.wrappedValue = $0 } }
            view.action = action
            view.accessibilityLabel = title
            view.accessibilityIdentifier = identifier
            view.isEnabled = enabled
        }
    }

    final class TouchView: UIView {
        var action: (() -> Void)?
        var onPress: ((Bool) -> Void)?
        var isEnabled = true {
            didSet {
                accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
                isUserInteractionEnabled = isEnabled
                if !isEnabled { finish() }
            }
        }
        /// How far outside the button a lift still counts, as for a Button.
        private static let slack = Metrics.minimumTouchTarget / 2
        private var touch: UITouch?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = false
            isAccessibilityElement = true
            accessibilityTraits = .button
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard isEnabled, touch == nil, let first = touches.first else { return }
            touch = first
            onPress?(true)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch, touches.contains(touch) else { return }
            onPress?(inside(touch))
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch, touches.contains(touch) else { return }
            let commit = isEnabled && inside(touch)
            finish()
            if commit { action?() }
        }

        /// A scroll took the touch, or the system cancelled it: no save.
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch, touches.contains(touch) else { return }
            finish()
        }

        override func accessibilityActivate() -> Bool {
            guard isEnabled else { return false }
            action?()
            return true
        }

        private func inside(_ touch: UITouch) -> Bool {
            bounds.insetBy(dx: -Self.slack, dy: -Self.slack).contains(touch.location(in: self))
        }

        private func finish() {
            touch = nil
            onPress?(false)
        }
    }
}
