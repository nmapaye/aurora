import AuroraCore
import SwiftUI

/// One signal: its label, value or honest empty state, when and where the
/// value came from, one line of context, and its one destination. Sample
/// data reads quieter than recorded data, and an estimate says so.
struct SignalCard: View {
    let model: SignalCardModel
    var symbol: String?
    var accent: Color = Palette.tint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                HStack(spacing: Metrics.xs) {
                    if let symbol {
                        Image(systemName: symbol)
                            .foregroundStyle(accent)
                            .accessibilityHidden(true)
                    }
                    Text(model.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                    if model.status == .sample {
                        Text("Sample")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(StatusTone.warning.foreground)
                            .padding(.horizontal, Metrics.xs)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(StatusTone.warning.background))
                    }
                }
                if model.status == .empty {
                    Text("No data")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Palette.textTertiary)
                } else if let value = model.value {
                    Text(value)
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(model.status == .sample ? Palette.textSecondary : Palette.textPrimary)
                }
                if !model.metaLine.isEmpty {
                    Text(model.metaLine)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(model.context)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Metrics.xxs) {
                    Text(model.destination)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.tint)
                .padding(.top, Metrics.xxs)
            }
            .padding(Metrics.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(model.status == .sample ? Palette.cardMuted : Palette.card)
            )
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.cardBorder))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityDescription)
        .accessibilityHint(model.destination)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("signal-\(model.id)")
    }
}
