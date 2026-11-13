import AuroraCore
import SwiftUI

/// "Why This Number": the captured estimate explained from the inputs the
/// model used. Everything shown comes from `AlertnessExplanation`, which
/// reads only the snapshot's `EnergyEstimate`. Sample Data and missing
/// inputs are labeled by the surrounding `EnergyEvidenceSections`.
struct WhyThisNumberCard: View {
    let estimate: EnergyEstimate
    let text: DateText

    var body: some View {
        let explanation = AlertnessExplanation.explain(estimate, text: text)
        VStack(alignment: .leading, spacing: Metrics.sm) {
            Text(explanation.headline)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(explanation.factors) { factor in
                VStack(alignment: .leading, spacing: Metrics.xxs) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
                            title(factor, largest: explanation.largest)
                            Spacer(minLength: 0)
                            if let points = factor.points { Text(points).font(Typography.value).monospacedDigit() }
                        }
                        VStack(alignment: .leading, spacing: Metrics.xxs) {
                            title(factor, largest: explanation.largest)
                            if let points = factor.points { Text(points).font(Typography.value).monospacedDigit() }
                        }
                    }
                    Text(factor.detail)
                        .font(Typography.source).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Metrics.xxs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(factor, largest: explanation.largest))
            }
            ForEach(explanation.notes, id: \.self) { note in
                Text(note).font(.footnote).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("why-this-number")
    }

    @ViewBuilder private func title(_ factor: AlertnessExplanation.Factor, largest: AlertnessExplanation.Factor.Kind?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
            Text(factor.title).font(Typography.label)
            if factor.kind == largest {
                Text("Largest part").font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func accessibilityLabel(_ factor: AlertnessExplanation.Factor, largest: AlertnessExplanation.Factor.Kind?) -> String {
        [factor.title, factor.kind == largest ? "largest part" : nil, factor.points.map { "\($0) points" }, factor.detail]
            .compactMap { $0 }.joined(separator: ". ")
    }
}
