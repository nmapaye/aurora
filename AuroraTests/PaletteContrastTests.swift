import SwiftUI
import Testing
import UIKit
@testable import Aurora

/// WCAG 2.2 AA contrast for every text color on every surface it is drawn
/// on, in light and dark, with and without Increase Contrast. This replaces
/// the accessibility audit's contrast check, which holds small text to a
/// stricter bar and samples whatever covers an element (see
/// AccessibilityAuditUITests). Disabled-control text is exempt under WCAG
/// 1.4.3 and isn't listed.
@MainActor
struct PaletteContrastTests {
    /// Body text: 4.5:1 (WCAG 1.4.3).
    static let text = 4.5
    /// Field edges and other component boundaries: 3:1 (WCAG 1.4.11).
    static let boundary = 3.0

    struct Pair: CustomTestStringConvertible {
        let name: String
        let foreground: Color
        let background: Color
        let minimum: Double
        var testDescription: String { name }
    }

    static let surfaces: [(String, Color)] = [
        ("screen", Palette.screen), ("card", Palette.card), ("cardMuted", Palette.cardMuted),
        ("modalBackground", Palette.modalBackground), ("fieldBackground", Palette.fieldBackground),
    ]

    static let pairs: [Pair] = {
        var pairs: [Pair] = []
        for (textName, color) in [("textPrimary", Palette.textPrimary), ("textSecondary", Palette.textSecondary),
                                  ("textTertiary", Palette.textTertiary), ("tint", Palette.tint), ("destructive", Palette.destructive)] {
            for (surfaceName, surface) in surfaces {
                pairs.append(Pair(name: "\(textName) on \(surfaceName)", foreground: color, background: surface, minimum: text))
            }
        }
        pairs += [
            Pair(name: "primaryButtonText on primaryButton", foreground: Palette.primaryButtonText, background: Palette.primaryButton, minimum: text),
            Pair(name: "secondaryButtonText on secondaryButton", foreground: Palette.secondaryButtonText, background: Palette.secondaryButton, minimum: text),
            Pair(name: "textPrimary on neutralButton", foreground: Palette.textPrimary, background: Palette.neutralButton, minimum: text),
            Pair(name: "tint on selectionFill", foreground: Palette.tint, background: Palette.selectionFill, minimum: text),
            Pair(name: "statusNeutralText on its background", foreground: Palette.statusNeutralText, background: Palette.statusNeutralBackground, minimum: text),
            Pair(name: "statusInfoText on its background", foreground: Palette.statusInfoText, background: Palette.statusInfoBackground, minimum: text),
            Pair(name: "statusSuccessText on its background", foreground: Palette.statusSuccessText, background: Palette.statusSuccessBackground, minimum: text),
            Pair(name: "statusWarningText on its background", foreground: Palette.statusWarningText, background: Palette.statusWarningBackground, minimum: text),
            Pair(name: "statusErrorText on its background", foreground: Palette.statusErrorText, background: Palette.statusErrorBackground, minimum: text),
            Pair(name: "fieldBorder on card", foreground: Palette.fieldBorder, background: Palette.card, minimum: boundary),
            Pair(name: "fieldBorder on fieldBackground", foreground: Palette.fieldBorder, background: Palette.fieldBackground, minimum: boundary),
        ]
        return pairs
    }()

    static let appearances: [(String, UITraitCollection)] = [
        ("light", UITraitCollection(traitsFrom: [.init(userInterfaceStyle: .light), .init(accessibilityContrast: .normal)])),
        ("dark", UITraitCollection(traitsFrom: [.init(userInterfaceStyle: .dark), .init(accessibilityContrast: .normal)])),
        ("light, Increase Contrast", UITraitCollection(traitsFrom: [.init(userInterfaceStyle: .light), .init(accessibilityContrast: .high)])),
        ("dark, Increase Contrast", UITraitCollection(traitsFrom: [.init(userInterfaceStyle: .dark), .init(accessibilityContrast: .high)])),
    ]

    @Test(arguments: pairs)
    func meetsAA(_ pair: Pair) {
        for (appearance, traits) in Self.appearances {
            let ratio = Self.contrast(pair.foreground, pair.background, traits)
            #expect(ratio >= pair.minimum, "\(pair.name), \(appearance): \(String(format: "%.2f", ratio)):1, needs \(pair.minimum):1")
        }
    }

    static func contrast(_ a: Color, _ b: Color, _ traits: UITraitCollection) -> Double {
        let la = luminance(UIColor(a).resolvedColor(with: traits))
        let lb = luminance(UIColor(b).resolvedColor(with: traits))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Relative luminance (WCAG 2.2), in sRGB.
    static func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        func linear(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
