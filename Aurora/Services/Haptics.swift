import UIKit

/// Haptics as the React Native build used them: success after a save, a
/// warning before a destructive change, a selection tick as the walkthrough
/// moves, and a light tap on each Reaction Test response.
@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
