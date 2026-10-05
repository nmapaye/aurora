import SwiftUI
import UIKit

// Warm ivory surfaces in light mode, deep ink in dark mode, and one sea-glass
// accent. Data accents are desaturated so charts stay quiet. Text roles meet
// WCAG AA on `card`.
enum Brand {
    static let ivory50 = 0xFFFDF8, ivory100 = 0xFBF8F2, ivory200 = 0xF6F2EA, ivory300 = 0xEFE9DE, ivory400 = 0xE6DFD2
    static let ink900 = 0x0F1317, ink850 = 0x151A1F, ink800 = 0x1C2227, ink700 = 0x262D33, ink600 = 0x343C43
    static let ink500 = 0x6E757C, ink400 = 0x8A9097, ink300 = 0xAEB3B8, ink100 = 0xF3EFE7
    static let sea800 = 0x17332F, sea700 = 0x1E6B64, sea600 = 0x2A7C73, sea300 = 0x7CC4B8, sea200 = 0xA7DBD1, sea100 = 0xE1EEEA
}

extension UIColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    /// A color that follows the current light or dark appearance.
    init(light: Int, dark: Int, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

enum Palette {
    static let screen = Color(light: Brand.ivory200, dark: Brand.ink900)
    static let modalBackground = Color(light: Brand.ivory100, dark: Brand.ink850)
    static let card = Color(light: Brand.ivory50, dark: Brand.ink850)
    static let cardMuted = Color(light: Brand.ivory300, dark: Brand.ink800)
    static let cardBorder = Color(light: Brand.ivory400, dark: Brand.ink700)
    static let separator = Color(light: Brand.ivory400, dark: Brand.ink700)
    static let textPrimary = Color(light: 0x1A1F24, dark: Brand.ink100)
    static let textSecondary = Color(light: 0x5B6168, dark: Brand.ink300)
    static let textTertiary = Color(light: 0x62676C, dark: Brand.ink400)
    static let tint = Color(light: Brand.sea700, dark: Brand.sea300)
    static let destructive = Color(light: 0xA8402E, dark: 0xE8806C)
    static let primaryButton = Color(light: Brand.sea700, dark: Brand.sea300)
    static let primaryButtonText = Color(light: Brand.ivory50, dark: Brand.ink900)
    static let primaryButtonDisabled = Color(light: Brand.ivory400, dark: Brand.ink800)
    static let primaryButtonDisabledText = Color(light: 0x767B80, dark: Brand.ink500)
    static let secondaryButton = Color(light: Brand.sea100, dark: Brand.sea800)
    static let secondaryButtonBorder = Color(light: 0xC5DDD7, dark: 0x24504A)
    static let secondaryButtonText = Color(light: Brand.sea700, dark: Brand.sea200)
    static let neutralButton = Color(light: Brand.ivory50, dark: Brand.ink800)
    static let neutralButtonBorder = Color(light: Brand.ivory400, dark: Brand.ink600)
    static let selectionFill = Color(light: Brand.sea100, dark: Brand.sea800)
    static let fieldBackground = Color(light: Brand.ivory100, dark: Brand.ink800)

    static let statusNeutralBackground = Color(light: Brand.ivory300, dark: Brand.ink800)
    static let statusNeutralText = Color(light: 0x5B6168, dark: 0xC3C8CD)
    static let statusInfoBackground = Color(light: Brand.sea100, dark: Brand.sea800)
    static let statusInfoText = Color(light: Brand.sea700, dark: Brand.sea200)
    static let statusSuccessBackground = Color(light: 0xE5EEE0, dark: 0x1D2B1C)
    static let statusSuccessText = Color(light: 0x46693A, dark: 0xA3C795)
    static let statusWarningBackground = Color(light: 0xF5EAD5, dark: 0x31281A)
    static let statusWarningText = Color(light: 0x855711, dark: 0xE6C27F)
    static let statusErrorBackground = Color(light: 0xF5E2DC, dark: 0x3A201B)
    static let statusErrorText = Color(light: 0x9E3B2A, dark: 0xF0A594)

    static let caffeineAccent = Color(light: 0x9A5B2E, dark: 0xD9A26E)
    static let activeCaffeineAccent = Color(light: 0x5E7A3E, dark: 0xA9C48A)
    static let sleepAccent = Color(light: 0x4A5590, dark: 0xA3ADE6)
    static let vigilanceAccent = Color(light: Brand.sea600, dark: Brand.sea300)
    static let cutoffAccent = Color(light: 0x7D4F80, dark: 0xCDA3D0)
    static let healthAccent = Color(light: 0xA8434F, dark: 0xE8939E)
    static let napAccent = Color(light: 0x3F7690, dark: 0x93C3DA)
}

enum Metrics {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    static let controlRadius: CGFloat = 12
    static let cardRadius: CGFloat = 16
    static let heroRadius: CGFloat = 24
    static let minimumTouchTarget: CGFloat = 44

    static let contentMaxWidth: CGFloat = 600
    static let wideContentMaxWidth: CGFloat = 1220
    /// Two columns only on iPad windows at least this wide.
    static let twoColumnMinWidth: CGFloat = 900
}

enum StatusTone {
    case neutral, info, success, warning, error

    var background: Color {
        switch self {
        case .neutral: Palette.statusNeutralBackground
        case .info: Palette.statusInfoBackground
        case .success: Palette.statusSuccessBackground
        case .warning: Palette.statusWarningBackground
        case .error: Palette.statusErrorBackground
        }
    }

    var foreground: Color {
        switch self {
        case .neutral: Palette.statusNeutralText
        case .info: Palette.statusInfoText
        case .success: Palette.statusSuccessText
        case .warning: Palette.statusWarningText
        case .error: Palette.statusErrorText
        }
    }
}

extension Font {
    /// Small uppercase label above grouped content.
    static let eyebrow = Font.footnote.weight(.semibold)
}
