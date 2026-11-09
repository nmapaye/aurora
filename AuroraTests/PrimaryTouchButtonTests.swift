import Testing
import UIKit
@testable import Aurora

/// Save's touch path is UIKit's (`PrimaryTouchButton`); the iPad keyboard
/// test (testDraftFieldKeepsSaveAboveCollapsedComposer) proves a real tap.
/// This covers what assistive input relies on: a button, once per
/// activation, and nothing while disabled.
@MainActor
@Suite struct PrimaryTouchButtonTests {
    @Test func activatesOnceAsAButtonAndNotWhileDisabled() {
        let view = PrimaryTouchButton.TouchView()
        var saves = 0
        view.action = { saves += 1 }
        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityTraits.contains(.button))
        #expect(view.accessibilityActivate())
        #expect(saves == 1)

        view.isEnabled = false
        #expect(view.accessibilityTraits.contains(.notEnabled))
        #expect(!view.isUserInteractionEnabled)
        #expect(!view.accessibilityActivate())
        #expect(saves == 1)
    }
}
