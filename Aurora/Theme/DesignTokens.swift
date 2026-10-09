import SwiftUI

enum Typography {
    static let cardTitle: Font = .headline
    static let evidence: Font = .body
    static let explanation: Font = .subheadline
    static let source: Font = .caption
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
}
