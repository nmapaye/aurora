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
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }
}

/// Reads `isEnabled` inside a view so it stays correct when the style is
/// wrapped by `AnyButtonStyle`, which calls `makeBody` directly.
private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
            .padding(.horizontal, Metrics.md)
            .foregroundStyle(isEnabled ? Palette.primaryButtonText : Palette.primaryButtonDisabledText)
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(isEnabled ? Palette.primaryButton : Palette.primaryButtonDisabled)
            )
            .pressFeedback(configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration)
    }
}

private struct SecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
            .padding(.horizontal, Metrics.md)
            .foregroundStyle(isEnabled ? Palette.secondaryButtonText : Palette.primaryButtonDisabledText)
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(isEnabled ? Palette.secondaryButton : Palette.primaryButtonDisabled)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(isEnabled ? Palette.secondaryButtonBorder : Palette.neutralButtonBorder)
            )
            .pressFeedback(configuration.isPressed)
    }
}

/// A compact state label: symbol plus text on a tone capsule, so state is
/// never carried by color alone.
struct StatusBadge: View {
    let text: String
    var tone: StatusTone = .neutral

    var body: some View {
        Label(text, systemImage: tone.symbol)
            .font(.footnote.weight(.medium))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, Metrics.sm)
            .padding(.vertical, Metrics.xxs)
            .background(Capsule().fill(tone.background))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A form field with its label above and an optional trailing unit, sharing
/// one field surface so labels, values and units align down a card.
struct LabeledField<Field: View>: View {
    let label: String
    var unit: String?
    @ViewBuilder var field: () -> Field
    /// True while the text field inside has keyboard focus.
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(label).font(Typography.label).foregroundStyle(Palette.textSecondary)
            HStack(spacing: Metrics.xs) {
                field()
                if let unit {
                    Text(unit).font(Typography.evidence).foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Metrics.sm)
            .frame(minHeight: Metrics.minimumTouchTarget)
            .focused($focused)
            .fieldSurface(focused: focused)
        }
    }
}

extension View {
    /// The shared field surface: fill, a resting border the card can't
    /// swallow, and a tint ring while the field has focus.
    func fieldSurface(focused: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        return background(Palette.fieldBackground, in: shape)
            .overlay(shape.strokeBorder(focused ? Palette.tint : Palette.fieldBorder, lineWidth: focused ? 2 : 1))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var auroraPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var auroraSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// "Saved", with a check that draws itself in and a success tap when the
/// save just happened in front of the person. Already-saved cards render
/// still. Reduce Motion shows the finished check without drawing.
struct SavedBadge: View {
    var text = "Saved"
    let celebrate: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1
    @State private var pop = false

    var body: some View {
        HStack(spacing: Metrics.xxs) {
            CheckMark(progress: progress)
                .stroke(StatusTone.success.foreground, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
                .padding(3)
                .background(Circle().fill(StatusTone.success.foreground.opacity(0.15)))
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(StatusTone.success.foreground)
        .padding(.horizontal, Metrics.sm)
        .padding(.vertical, Metrics.xxs)
        .background(StatusTone.success.background, in: Capsule())
        .scaleEffect(pop ? 1.08 : 1)
        .accessibilityElement(children: .combine)
        .sensoryFeedback(.success, trigger: celebrate) { _, now in now }
        .onChange(of: celebrate, initial: true) { _, now in
            guard now, !reduceMotion else { return }
            progress = 0
            withAnimation(.easeOut(duration: 0.32).delay(0.05)) { progress = 1 }
            withAnimation(Motion.pressSpring) { pop = true }
            withAnimation(Motion.pressSpring.delay(0.18)) { pop = false }
        }
    }
}

private struct CheckMark: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.1))
        return path.trimmedPath(from: 0, to: progress)
    }
}
