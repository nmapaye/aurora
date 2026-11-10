import SwiftUI

/// An (i) button that shows a row's explanation only when asked. The
/// explanation is extra context, never the only place a value or an action
/// lives.
struct InfoButton: View {
    let topic: String
    @Binding var isShown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { isShown.toggle() }
        } label: {
            Image(systemName: isShown ? "info.circle.fill" : "info.circle")
                .font(.body)
                .foregroundStyle(Palette.tint)
                .frame(width: Metrics.minimumTouchTarget, height: Metrics.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        // Borderless so a Form row's other control keeps its own taps.
        .buttonStyle(.borderless)
        .accessibilityLabel("About \(topic)")
        .accessibilityHint(isShown ? "Hides the explanation." : "Shows an explanation.")
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }
}

/// The explanation an `InfoButton` reveals: one consistent style and
/// placement, aligned with the row's leading edge.
struct InfoText: View {
    let text: String
    var id: String = ""

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(id)
            .transition(.opacity)
    }
}

/// A row whose explanation stays hidden until its info button is tapped.
struct ExplainedRow<Content: View>: View {
    let topic: String
    let info: String
    var infoID: String = ""
    @ViewBuilder let content: Content
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Metrics.xs) {
                content.frame(maxWidth: .infinity, alignment: .leading)
                InfoButton(topic: topic, isShown: $shown)
            }
            if shown { InfoText(text: info, id: infoID) }
        }
    }
}
