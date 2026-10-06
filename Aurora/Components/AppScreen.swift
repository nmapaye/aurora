import SwiftUI

/// The screen scaffold: a scrolling column on the screen color with a large
/// title, optional subtitle, and a trailing settings button. Content is
/// capped at a readable width and centered on wide windows.
struct AppScreen<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var showsSettings = true
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(Router.self) private var router

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= Metrics.twoColumnMinWidth && sizeClass == .regular
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.xl) {
                    header
                    content()
                }
                .frame(maxWidth: wide ? Metrics.wideContentMaxWidth : Metrics.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, wide ? Metrics.lg : Metrics.md)
                .padding(.bottom, Metrics.xxl)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .environment(\.isWideLayout, wide)
        }
        .background(Palette.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
            VStack(alignment: .leading, spacing: Metrics.xxs) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("screen-title-\(title)")
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer(minLength: Metrics.sm)
            trailing()
            if showsSettings {
                Button {
                    router.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .frame(width: Metrics.minimumTouchTarget, height: Metrics.minimumTouchTarget)
                        .background(Circle().fill(Palette.card))
                        .overlay(Circle().strokeBorder(Palette.cardBorder))
                }
                .foregroundStyle(Palette.tint)
                .accessibilityLabel("Open settings")
            }
        }
        .padding(.top, Metrics.md)
    }
}

extension AppScreen where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, showsSettings: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.showsSettings = showsSettings
        self.trailing = { EmptyView() }
        self.content = content
    }
}

private struct WideLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Two-column iPad layout.
    var isWideLayout: Bool {
        get { self[WideLayoutKey.self] }
        set { self[WideLayoutKey.self] = newValue }
    }
}

/// A raised card surface.
struct Card<Content: View>: View {
    var padding: CGFloat = Metrics.md
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sm, content: content)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.cardBorder))
    }
}

/// Small uppercase label above grouped content.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.eyebrow)
            .tracking(0.6)
            .foregroundStyle(Palette.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One line of status text on a tinted capsule.
struct StatusText: View {
    let text: String
    var tone: StatusTone = .neutral

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, Metrics.sm)
            .padding(.vertical, Metrics.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(tone.background))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
            .padding(.horizontal, Metrics.md)
            .foregroundStyle(isEnabled ? Palette.primaryButtonText : Palette.primaryButtonDisabledText)
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(isEnabled ? Palette.primaryButton : Palette.primaryButtonDisabled)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
            .padding(.horizontal, Metrics.md)
            .foregroundStyle(Palette.secondaryButtonText)
            .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(Palette.secondaryButton))
            .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).strokeBorder(Palette.secondaryButtonBorder))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var auroraPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var auroraSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
